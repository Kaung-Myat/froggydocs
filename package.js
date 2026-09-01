#!/usr/bin/env node

const { spawn } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const https = require('https');
const os = require('os');
const path = require('path');

const { version: PACKAGE_VERSION } = require('./package.json');
const GITHUB_REPOSITORY = 'Kaung-Myat/froggydocs';
const SUPPORTED_TARGETS = new Set([
  'linux-x64',
  'linux-arm64',
  'darwin-x64',
  'darwin-arm64',
  'win32-x64'
]);

function getTarget(platform = os.platform(), arch = os.arch()) {
  const target = `${platform}-${arch}`;
  if (!SUPPORTED_TARGETS.has(target)) {
    throw new Error(
      `Unsupported platform: ${target}. Supported targets: ${[...SUPPORTED_TARGETS].join(', ')}`
    );
  }
  return target;
}

function getAssetName(platform = os.platform(), arch = os.arch()) {
  getTarget(platform, arch);
  const extension = platform === 'win32' ? '.exe' : '';
  return `froggy-docs-${platform}-${arch}${extension}`;
}

function getInstallDir() {
  const root = process.env.FROGGY_DOCS_INSTALL_DIR || path.join(os.homedir(), '.froggy-docs');
  return path.join(root, PACKAGE_VERSION);
}

function getBinaryPath(platform = os.platform()) {
  const extension = platform === 'win32' ? '.exe' : '';
  return path.join(getInstallDir(), `froggy-docs${extension}`);
}

function getReleaseUrls(assetName) {
  const releaseRoot = `https://github.com/${GITHUB_REPOSITORY}/releases/download/v${PACKAGE_VERSION}`;
  const binaryUrl = process.env.FROGGY_DOCS_BINARY_URL || `${releaseRoot}/${assetName}`;
  const checksumUrl = process.env.FROGGY_DOCS_CHECKSUM_URL ||
    new URL('checksums.txt', binaryUrl).toString();
  return { binaryUrl, checksumUrl };
}

function parseChecksumManifest(manifest, assetName) {
  for (const line of manifest.split(/\r?\n/)) {
    const match = line.trim().match(/^([a-fA-F0-9]{64})\s+\*?(.+)$/);
    if (match && match[2] === assetName) return match[1].toLowerCase();
  }
  throw new Error(`Checksum for ${assetName} was not found in checksums.txt`);
}

function sha256File(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const input = fs.createReadStream(filePath);
    input.on('error', reject);
    input.on('data', chunk => hash.update(chunk));
    input.on('end', () => resolve(hash.digest('hex')));
  });
}

function requestUrl(url, onResponse, redirectsRemaining = 5) {
  const parsedUrl = new URL(url);
  if (parsedUrl.protocol !== 'https:') {
    return Promise.reject(new Error(`Refusing insecure download URL: ${parsedUrl.protocol}`));
  }
  return new Promise((resolve, reject) => {
    const request = https.get(parsedUrl, {
      headers: { 'User-Agent': `froggy-docs-npm/${PACKAGE_VERSION}` }
    }, response => {
      if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
        response.resume();
        if (redirectsRemaining === 0) {
          reject(new Error('Too many redirects'));
          return;
        }
        const redirectUrl = new URL(response.headers.location, parsedUrl).toString();
        resolve(requestUrl(redirectUrl, onResponse, redirectsRemaining - 1));
        return;
      }
      if (response.statusCode !== 200) {
        response.resume();
        reject(new Error(`Download returned HTTP ${response.statusCode}`));
        return;
      }
      resolve(onResponse(response));
    });
    request.on('error', reject);
    request.setTimeout(30000, () => request.destroy(new Error('Download timed out')));
  });
}

function downloadText(url) {
  return requestUrl(url, response => new Promise((resolve, reject) => {
    const chunks = [];
    let received = 0;
    response.on('data', chunk => {
      received += chunk.length;
      if (received > 1024 * 1024) {
        response.destroy(new Error('Checksum manifest is unexpectedly large'));
        return;
      }
      chunks.push(chunk);
    });
    response.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    response.on('error', reject);
  }));
}

function downloadFile(url, destination) {
  return requestUrl(url, response => new Promise((resolve, reject) => {
    const output = fs.createWriteStream(destination, { flags: 'wx', mode: 0o600 });
    response.pipe(output);
    response.on('error', reject);
    output.on('error', reject);
    output.on('finish', () => output.close(resolve));
  }));
}

async function downloadAndInstall() {
  const platform = os.platform();
  const arch = os.arch();
  const assetName = getAssetName(platform, arch);
  const binaryPath = getBinaryPath(platform);
  if (fs.existsSync(binaryPath)) return binaryPath;

  const installDir = getInstallDir();
  fs.mkdirSync(installDir, { recursive: true, mode: 0o700 });
  const temporaryPath = `${binaryPath}.${process.pid}.download`;
  const { binaryUrl, checksumUrl } = getReleaseUrls(assetName);

  console.log(`Installing FroggyDocs ${PACKAGE_VERSION} for ${getTarget(platform, arch)}...`);
  try {
    const manifest = await downloadText(checksumUrl);
    const expectedChecksum = parseChecksumManifest(manifest, assetName);
    await downloadFile(binaryUrl, temporaryPath);
    const actualChecksum = await sha256File(temporaryPath);
    if (!crypto.timingSafeEqual(
      Buffer.from(actualChecksum, 'hex'),
      Buffer.from(expectedChecksum, 'hex')
    )) {
      throw new Error(`SHA-256 verification failed for ${assetName}`);
    }
    if (platform !== 'win32') fs.chmodSync(temporaryPath, 0o755);
    fs.renameSync(temporaryPath, binaryPath);
    console.log(`FroggyDocs ${PACKAGE_VERSION} installed and verified.`);
    return binaryPath;
  } catch (error) {
    if (fs.existsSync(temporaryPath)) fs.unlinkSync(temporaryPath);
    throw new Error(`Unable to install FroggyDocs: ${error.message}`);
  }
}

async function runCommand(args) {
  const binaryPath = fs.existsSync(getBinaryPath())
    ? getBinaryPath()
    : await downloadAndInstall();
  return new Promise((resolve, reject) => {
    const child = spawn(binaryPath, args, {
      stdio: 'inherit',
      shell: false,
      env: {
        ...process.env,
        FROGGY_DOCS_WEB_DIR: path.join(__dirname, 'frontend', 'web')
      }
    });
    child.on('close', code => resolve(code == null ? 1 : code));
    child.on('error', reject);
  });
}

function printHelp() {
  console.log(`
FroggyDocs v${PACKAGE_VERSION}

Usage:
  froggy-docs serve       Start live API documentation
  froggy-docs watch       Watch source files and regenerate the specification
  froggy-docs build       Generate a complete deployable static site
  froggy-docs install     Download and verify this version's native binary

Options:
  -p, --port <port>       Server port (default: 8080)
  -x, --proxy <url>       Proxy API requests to a backend URL
  -o, --output <path>     Specification JSON path or static build directory
  --dist <path>           Static deployment output directory
  --base-path <path>      Documentation path such as /docs/api/
  --project <path>        API project directory to scan

Examples:
  froggy-docs serve --project ./my-api --proxy http://localhost:3000
  froggy-docs build --project ./my-api --output dist
  froggy-docs serve --project ./my-api --base-path /docs/api/
`);
}

async function main(args = process.argv.slice(2)) {
  const command = args[0];
  if (!command || command === '--help' || command === '-h' || command === 'help') {
    printHelp();
    return 0;
  }
  if (command === '--version' || command === '-v') {
    console.log(PACKAGE_VERSION);
    return 0;
  }
  if (command === 'install') {
    await downloadAndInstall();
    return 0;
  }
  if (command === 'generate') args[0] = 'build';
  if (!['serve', 'watch', 'build'].includes(args[0])) {
    throw new Error(`Unknown command: ${command}. Run froggy-docs --help.`);
  }
  return runCommand(args);
}

if (require.main === module) {
  main().then(code => {
    process.exitCode = code;
  }).catch(error => {
    console.error(`Error: ${error.message}`);
    process.exitCode = 1;
  });
}

module.exports = {
  PACKAGE_VERSION,
  SUPPORTED_TARGETS,
  downloadAndInstall,
  getAssetName,
  getBinaryPath,
  getInstallDir,
  getReleaseUrls,
  getTarget,
  main,
  parseChecksumManifest,
  sha256File
};
