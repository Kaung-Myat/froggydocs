#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const packageVersion = require(path.join(root, 'package.json')).version;
const pubspec = fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8');
const versionSource = fs.readFileSync(path.join(root, 'lib', 'src', 'version.dart'), 'utf8');
const pubspecVersion = pubspec.match(/^version:\s*(\S+)\s*$/m)?.[1];
const dartVersion = versionSource.match(/froggyDocsVersion\s*=\s*['"]([^'"]+)['"]/)?.[1];

const versions = {
  'package.json': packageVersion,
  'pubspec.yaml': pubspecVersion,
  'lib/src/version.dart': dartVersion
};
for (const [source, version] of Object.entries(versions)) {
  if (version !== packageVersion) {
    throw new Error(`Version mismatch: ${source} is ${version}, expected ${packageVersion}`);
  }
}

const tag = process.env.GITHUB_REF_NAME;
if (tag && tag !== `v${packageVersion}`) {
  throw new Error(`Release tag ${tag} does not match package version v${packageVersion}`);
}

console.log(`Version ${packageVersion} is synchronized.`);
