#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ranks = { info: 0, low: 1, moderate: 2, high: 3, critical: 4 };

function evaluateAudit(audit, lock, policy, now = Date.now(), registryVersions = {}) {
    if (!audit || audit.error || !audit.vulnerabilities || !audit.metadata?.vulnerabilities) {
        throw new Error('npm did not return a valid audit report');
    }
    const findings = audit.vulnerabilities;
    const threshold = ranks[policy.minimumSeverity];
    if (threshold === undefined) throw new Error('Invalid audit severity policy');

    function approved(name, ancestors = new Set()) {
        if (ancestors.has(name)) return false;
        const finding = findings[name];
        if (!finding || !Array.isArray(finding.via) || finding.via.length === 0 || !finding.nodes?.length) return false;
        if (!finding.nodes.every(node => lock.packages?.[node]?.dev === true)) return false;
        const next = new Set(ancestors).add(name);
        return finding.via.every(via => {
            if (typeof via === 'string') return approved(via, next);
            const id = via.url?.match(/\/advisories\/(GHSA-[\w-]+)$/)?.[1];
            const exception = policy.exceptions?.[id];
            if (!exception || exception.package !== name || !exception.developmentOnly) return false;
            if (!Number.isFinite(Date.parse(exception.expires)) || now >= Date.parse(exception.expires)) return false;
            // npm's fixAvailable can propose replacing/downgrading callers even
            // when this leaf has no patch. Check the actual published release.
            if (registryVersions[name] !== exception.publishedLatest) return false;
            return finding.nodes.every(node => exception.versions.includes(lock.packages[node].version));
        });
    }

    const blocked = [];
    const allowed = [];
    for (const [name, finding] of Object.entries(findings)) {
        if (ranks[finding.severity] === undefined) throw new Error(`Unknown severity for ${name}`);
        if (ranks[finding.severity] < threshold) continue;
        (approved(name) ? allowed : blocked).push(name);
    }
    return { blocked, allowed, counts: audit.metadata.vulnerabilities };
}

function main() {
    const root = path.resolve(__dirname, '..');
    // npm_execpath is supplied by npm run and avoids Windows shell quoting.
    const npmCli = process.env.npm_execpath;
    if (!npmCli || !fs.existsSync(npmCli)) throw new Error('Run this check using npm run audit');
    const result = spawnSync(process.execPath, [npmCli, 'audit', '--json'], {
        cwd: root, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024, timeout: 120000, windowsHide: true,
    });
    if (result.error || result.status === null) throw new Error('npm audit could not finish');
    let audit;
    try { audit = JSON.parse(result.stdout); } catch { throw new Error('npm audit returned invalid JSON'); }
    const lock = JSON.parse(fs.readFileSync(path.join(root, 'package-lock.json'), 'utf8'));
    const policy = JSON.parse(fs.readFileSync(path.join(root, 'security', 'npm-audit-policy.json'), 'utf8'));
    const registryVersions = {};
    for (const exception of Object.values(policy.exceptions || {})) {
        const lookup = spawnSync(process.execPath, [npmCli, 'view', exception.package, 'version', '--json'], {
            cwd: root, encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024, windowsHide: true,
        });
        if (lookup.error || lookup.status !== 0) throw new Error(`Could not verify upstream version for ${exception.package}`);
        try { registryVersions[exception.package] = JSON.parse(lookup.stdout); }
        catch { throw new Error('Registry returned invalid version data'); }
    }
    const checked = evaluateAudit(audit, lock, policy, Date.now(), registryVersions);
    console.log(`Raw audit: ${checked.counts.high} high, ${checked.counts.critical} critical, ${checked.counts.moderate} moderate`);
    if (checked.allowed.length) console.log(`Temporary development-only exception: ${checked.allowed.join(', ')}. See docs/SECURITY.md.`);
    if (checked.blocked.length) throw new Error(`Unapproved dependency findings: ${checked.blocked.join(', ')}`);
    console.log('No unapproved findings at high severity or above');
}

module.exports = { evaluateAudit };
if (require.main === module) {
    try { main(); } catch (error) { console.error(error.message); process.exitCode = 1; }
}
