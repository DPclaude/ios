import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { releaseMetadata } from './release-metadata.mjs';

test('SideStore source and app update share a version, bundle, direct URL and exact file size', () => {
  const dir = mkdtempSync(join(tmpdir(), 'planner-release-'));
  try {
    const ipa = join(dir, 'Planner.ipa'); writeFileSync(ipa, new Uint8Array(123));
    const { source, update } = releaseMetadata({ version: '1.1.0', ipa, notes: '桌面计划', date: '2026-09-29T00:00:00Z' });
    assert.equal(update.version, '1.1.0');
    assert.equal(update.downloadURL, 'https://github.com/DPclaude/ios/releases/download/native-v1.1.0/Planner.ipa');
    assert.equal(source.apps[0].bundleIdentifier, 'com.dpclaude.planner');
    assert.equal(source.apps[0].versions[0].downloadURL, update.downloadURL);
    assert.equal(source.apps[0].versions[0].size, 123);
    assert.equal(source.apps[0].versions[0].version, update.version);
    assert.equal(source.apps[0].versions[0].minOSVersion, '17.0');
    assert.equal(source.apps[0].marketplaceID, undefined);
    assert.equal(source.apps[0].versions[0].buildVersion, undefined);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
test('invalid versions and empty IPA cannot produce a release', () => {
  const dir = mkdtempSync(join(tmpdir(), 'planner-release-'));
  try {
    const ipa = join(dir, 'Planner.ipa'); writeFileSync(ipa, '');
    assert.throws(() => releaseMetadata({ version: '1.1.0', ipa, notes: '' }));
    writeFileSync(ipa, 'ipa');
    for (const version of ['1.2', 'v1.2.3', '../x', '01.2.3']) assert.throws(() => releaseMetadata({ version, ipa, notes: '' }));
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
