#!/usr/bin/env node

/**
 * FroggyDocs - npm wrapper that downloads and runs the Dart executable
 * This script handles installation and provides CLI interface
 */

const { execSync, spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');
const https = require('https');
const zlib = require('zlib');
const { createReadStream, createWriteStream } = require('fs');
const { pipeline } = require('stream');

const PACKAGE_VERSION = '1.0.0';
const PACKAGE_NAME = 'froggy-docs';

function getInstallDir() {
  return path.join(os.homedir(), '.froggy-docs');
}

function getBinaryPath() {
  const ext = os.platform() === 'win32' ? '.exe' : '';
  return path.join(getInstallDir(), `froggy-docs${ext}`);
}

async function downloadAndInstall() {
  const installDir = getInstallDir();
  const binaryPath = getBinaryPath();
  
  if (fs.existsSync(binaryPath)) {
    console.log('✅ FroggyDocs already installed');
    return binaryPath;
  }

  console.log('📦 Installing FroggyDocs...');
  
  if (!fs.existsSync(installDir)) {
    fs.mkdirSync(installDir, { recursive: true });
  }

  // For now, we provide instructions since we're not hosting the binary
  // In production, upload the compiled binary to GitHub releases
  console.log('⚠️  Manual installation required:');
  console.log('   1. Download from: https://github.com/yourusername/froggy-docs/releases');
  console.log('   2. Extract to:', installDir);
  console.log('   3. Rename to: froggy-docs' + (os.platform() === 'win32' ? '.exe' : ''));
  
  return null;
}

function runCommand(args) {
  const binaryPath = getBinaryPath();
  
  if (!fs.existsSync(binaryPath)) {
    console.error('❌ FroggyDocs not installed. Run: froggy-docs install');
    process.exit(1);
  }

  return new Promise((resolve, reject) => {
    const child = spawn(binaryPath, args, {
      stdio: 'inherit',
      shell: os.platform() === 'win32'
    });
    
    child.on('close', (code) => {
      process.exit(code);
    });
    
    child.on('error', reject);
  });
}

async function main() {
  const args = process.argv.slice(2);
  const command = args[0];

  if (!command || command === '--help' || command === '-h') {
    console.log(`
🐸 FroggyDocs v${PACKAGE_VERSION}

Install:
  froggy-docs install     Install the Dart runtime and binary

Usage:
  froggy-docs serve       Start server with live documentation
  froggy-docs watch       Watch for changes and regenerate docs
  froggy-docs generate    Generate static documentation
  froggy-docs help       Show this help message

Options:
  -p, --port <port>     Port number (default: 8080)
  -h, --host <host>     Host address (default: localhost)
  --project <path>      Project directory to scan

Examples:
  froggy-docs serve --port 3000
  froggy-docs serve --host 0.0.0.0 --port 8080
  froggy-docs watch --project ./my-api
`);
    return;
  }

  switch (command) {
    case 'install':
      await downloadAndInstall();
      break;
    
    case 'serve':
    case 'watch':
    case 'generate':
      await runCommand(args);
      break;
    
    default:
      console.error(`Unknown command: ${command}`);
      console.log('Run: froggy-docs --help');
      process.exit(1);
  }
}

main().catch(console.error);