#!/usr/bin/env node
const path = require("node:path");
const fs = require("node:fs");

const rokuDeploy = require("roku-deploy");

const HOST = process.env.ROKU_HOST || "192.168.0.157";
const PASSWORD = process.env.ROKU_PASSWORD || "oscarjo";
const ROOT_DIR = path.resolve(__dirname, "..");
const OUT_DIR = path.join(ROOT_DIR, "out");
const OUT_FILE = "Stitch-Revitalized-For-Roku";

function fail(msg) {
    console.error(`error: ${msg}`);
    process.exit(1);
}

function readSigningPassword() {
    const cliArg = process.argv[2];
    if (cliArg && cliArg.trim()) return cliArg.trim();
    if (process.env.ROKU_SIGNING_PASSWORD) return process.env.ROKU_SIGNING_PASSWORD;
    fail(
        "missing signing password\n" +
        "usage:  node scripts/sign-package.js <signing-password>\n" +
        "  or:   ROKU_SIGNING_PASSWORD=... node scripts/sign-package.js"
    );
}

function readManifest() {
    const text = fs.readFileSync(path.join(ROOT_DIR, "manifest"), "utf8");
    const get = (k) => {
        const m = text.match(new RegExp(`^${k}=(.*)$`, "m"));
        return m ? m[1].trim() : null;
    };
    const title = get("title") || fail("manifest missing title");
    const major = get("major_version") || fail("manifest missing major_version");
    const minor = get("minor_version") || fail("manifest missing minor_version");
    const build = get("build_version") || "0";
    return { title, major, minor, build, version: `${major}.${minor}.${build}` };
}

async function main() {
    const signingPassword = readSigningPassword();
    const manifest = readManifest();

    fs.mkdirSync(OUT_DIR, { recursive: true });

    const options = {
        host: HOST,
        password: PASSWORD,
        signingPassword,
        rootDir: ROOT_DIR,
        outDir: OUT_DIR,
        outFile: OUT_FILE,
        files: [
            "manifest",
            "source/**/*",
            "components/**/*",
            "images/**/*",
            "fonts/**/*",
            "locale/**/*",
            "settings/**/*",
        ],
        retainStagingDir: false,
    };

    console.log(`>>  ${manifest.title} v${manifest.version}`);
    console.log(`>>  TV: ${HOST}`);
    console.log(`>>  Output: ${path.join(OUT_DIR, OUT_FILE)}.pkg`);
    console.log("");
    console.log(">>  [1/3] zipping + sideloading to TV...");
    console.log(">>  [2/3] signing package on TV...");
    console.log(">>  [3/3] downloading signed .pkg...");
    console.log("");

    const pkgPath = await rokuDeploy.deployAndSignPackage(options);
    console.log("");
    console.log(`>>  signed package: ${pkgPath}`);

    const stats = fs.statSync(pkgPath);
    console.log(`>>  size: ${(stats.size / 1024).toFixed(1)} KB`);

    console.log("");
    console.log(">>  fetching DevID for sanity check...");
    try {
        const devId = await rokuDeploy.getDevId({ host: HOST, password: PASSWORD });
        console.log(`>>  DevID: ${devId}`);
        console.log(">>  Verify this matches the DevID on the Roku Developer Dashboard");
        console.log(">>  for channel 817397 before uploading.");
    } catch (err) {
        console.warn(`>>  (could not fetch DevID: ${err.message})`);
    }

    console.log("");
    console.log(">>  Done. Upload the .pkg to the Roku Developer Dashboard:");
    console.log(`>>    ${pkgPath}`);
}

main().catch((err) => {
    console.error("");
    console.error("FAILED:", err.message || err);
    if (err && err.results && err.results.body) {
        const body = String(err.results.body).slice(0, 500);
        console.error("device response (first 500 chars):", body);
    }
    process.exit(1);
});
