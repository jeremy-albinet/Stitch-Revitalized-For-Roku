#!/usr/bin/env node
const path = require("node:path");
const fs = require("node:fs");

const rokuDeploy = require("roku-deploy");

const ROOT_DIR = path.resolve(__dirname, "..");
const OUT_DIR = path.join(ROOT_DIR, "out");
const OUT_FILE = "Stitch-Revitalized-For-Roku";

function fail(msg) {
    console.error(`error: ${msg}`);
    process.exit(1);
}

const HOST = process.env.ROKU_HOST || fail("missing ROKU_HOST env var\nusage: ROKU_HOST=<ip> ROKU_PASSWORD=<pw> ROKU_SIGNING_PASSWORD=<pw> npm run sign");
const PASSWORD = process.env.ROKU_PASSWORD || fail("missing ROKU_PASSWORD env var\nusage: ROKU_HOST=<ip> ROKU_PASSWORD=<pw> ROKU_SIGNING_PASSWORD=<pw> npm run sign");

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

    const zipPath = path.join(OUT_DIR, `${OUT_FILE}.zip`);
    if (!fs.existsSync(zipPath)) {
        fail(`pre-built zip not found at ${zipPath} — run 'npm run package' first`);
    }

    const baseOptions = {
        host: HOST,
        password: PASSWORD,
        outDir: OUT_DIR,
        outFile: OUT_FILE,
    };

    console.log(`>>  ${manifest.title} v${manifest.version}`);
    console.log(`>>  TV: ${HOST}`);
    console.log(`>>  Output: ${path.join(OUT_DIR, OUT_FILE)}.pkg`);
    console.log("");
    console.log(">>  [1/3] sideloading pre-built zip to TV...");
    console.log(">>  [2/3] signing package on TV...");
    console.log(">>  [3/3] downloading signed .pkg...");
    console.log("");

    await rokuDeploy.publish(baseOptions);
    const remotePkgPath = await rokuDeploy.signExistingPackage({ ...baseOptions, signingPassword });
    const pkgPath = await rokuDeploy.retrieveSignedPackage(remotePkgPath, baseOptions);
    console.log("");
    console.log(`>>  signed package: ${pkgPath}`);

    const stats = fs.statSync(pkgPath);
    console.log(`>>  size: ${(stats.size / 1024).toFixed(1)} KB`);

    console.log("");
    console.log(">>  fetching DevID for sanity check...");
    try {
        const deviceInfo = await rokuDeploy.getDeviceInfo({ host: HOST, password: PASSWORD });
        const devId = deviceInfo["keyed-developer-id"];
        console.log(`>>  DevID: ${devId}`);
        console.log(">>  Verify this matches the DevID on the Roku Developer Dashboard before uploading.");
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
