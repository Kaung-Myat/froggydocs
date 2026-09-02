const assert = require('node:assert/strict');
const childProcess = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const wrapper = require('../package.js');

function runVersionVerification(refType, refName) {
  return childProcess.spawnSync(process.execPath, ['scripts/verify-version.js'], {
    cwd: path.resolve(__dirname, '..'),
    encoding: 'utf8',
    env: {
      ...process.env,
      GITHUB_REF_TYPE: refType,
      GITHUB_REF_NAME: refName
    }
  });
}

test('uses a versioned installation directory', () => {
  const original = process.env.FROGGY_DOCS_INSTALL_DIR;
  const root = path.join(os.tmpdir(), 'froggy-docs-wrapper-test');
  process.env.FROGGY_DOCS_INSTALL_DIR = root;
  try {
    assert.equal(wrapper.getInstallDir(), path.join(root, wrapper.PACKAGE_VERSION));
    assert.equal(
      wrapper.getBinaryPath('linux'),
      path.join(root, wrapper.PACKAGE_VERSION, 'froggy-docs')
    );
    assert.equal(
      wrapper.getBinaryPath('win32'),
      path.join(root, wrapper.PACKAGE_VERSION, 'froggy-docs.exe')
    );
  } finally {
    if (original == null) delete process.env.FROGGY_DOCS_INSTALL_DIR;
    else process.env.FROGGY_DOCS_INSTALL_DIR = original;
  }
});

test('maps supported platforms to release asset names', () => {
  assert.equal(wrapper.getAssetName('linux', 'x64'), 'froggy-docs-linux-x64');
  assert.equal(wrapper.getAssetName('linux', 'arm64'), 'froggy-docs-linux-arm64');
  assert.equal(wrapper.getAssetName('darwin', 'arm64'), 'froggy-docs-darwin-arm64');
  assert.equal(wrapper.getAssetName('win32', 'x64'), 'froggy-docs-win32-x64.exe');
  assert.throws(() => wrapper.getAssetName('freebsd', 'x64'), /Unsupported platform/);
});

test('parses only an exact checksum manifest entry', () => {
  const hash = 'a'.repeat(64);
  const manifest = `${'b'.repeat(64)}  another-file\n${hash} *froggy-docs-linux-x64\n`;
  assert.equal(
    wrapper.parseChecksumManifest(manifest, 'froggy-docs-linux-x64'),
    hash
  );
  assert.throws(
    () => wrapper.parseChecksumManifest(manifest, 'froggy-docs-linux'),
    /was not found/
  );
});

test('calculates a binary SHA-256 digest', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'froggy-docs-sha-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const file = path.join(directory, 'binary');
  fs.writeFileSync(file, 'froggy-docs');
  const expected = crypto.createHash('sha256').update('froggy-docs').digest('hex');
  assert.equal(await wrapper.sha256File(file), expected);
});

test('derives binary and checksum URLs from the package version', () => {
  const asset = 'froggy-docs-linux-x64';
  const { binaryUrl, checksumUrl } = wrapper.getReleaseUrls(asset);
  assert.match(binaryUrl, new RegExp(`/v${wrapper.PACKAGE_VERSION}/${asset}$`));
  assert.match(checksumUrl, new RegExp(`/v${wrapper.PACKAGE_VERSION}/checksums\\.txt$`));
});

test('allows version verification on a normal CI branch', () => {
  const result = runVersionVerification('branch', 'main');
  assert.equal(result.status, 0, result.stderr);
});

test('accepts only the matching tag for a release run', () => {
  const matching = runVersionVerification('tag', `v${wrapper.PACKAGE_VERSION}`);
  assert.equal(matching.status, 0, matching.stderr);

  const mismatched = runVersionVerification('tag', 'v0.0.0');
  assert.notEqual(mismatched.status, 0);
  assert.match(mismatched.stderr, /does not match package version/);
});
