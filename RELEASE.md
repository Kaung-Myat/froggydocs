# FroggyDocs release process

FroggyDocs is distributed on npm as a small Node.js launcher. The launcher
downloads the matching native executable from the GitHub Release with the same
version and verifies it against `checksums.txt` before installation.

## One-time npm setup

1. Create or claim the `froggy-docs` npm package.
2. Enable two-factor authentication on the maintainer account.
3. In the npm package settings, add a GitHub Actions trusted publisher:
   - Repository: `Kaung-Myat/froggydocs`
   - Workflow: `release.yml`
   - Environment: `npm`
   - Allowed action: `npm publish`
4. Create a protected GitHub environment named `npm`. Requiring manual
   approval is recommended for the beta period.
5. Protect version tags so only maintainers can create `v*` tags.

No long-lived npm token is required by the release workflow.

## Prepare a release

Keep these versions identical:

- `package.json`
- `pubspec.yaml`
- `lib/src/version.dart`
- Git tag, prefixed with `v`

Verify the release locally:

```bash
dart pub get
dart analyze
dart test
npm run verify-version
npm test
npm pack --dry-run
```

For a beta release, use a prerelease version such as `1.3.0-beta.1`. The
workflow publishes prerelease versions with the npm `beta` distribution tag;
stable versions use `latest`.

## Publish

After merging the release commit to `main`:

```bash
git tag v1.3.0-beta.1
git push origin v1.3.0-beta.1
```

The release workflow performs the following operations in order:

1. Runs Dart and Node.js tests and verifies version synchronization.
2. Builds Linux x64/arm64, macOS x64/arm64, and Windows x64 executables.
3. Creates `checksums.txt` with SHA-256 hashes.
4. Publishes the binaries and checksum manifest to GitHub Releases.
5. Downloads and verifies the released Linux binary through the npm launcher.
6. Publishes the npm package through trusted publishing.

Do not run `npm publish` before the GitHub Release assets exist. A launcher
published without its matching native binaries cannot install successfully.

## Verify a beta

```bash
npm install --global froggy-docs@beta
froggy-docs --version
froggy-docs build --project ./example-api --output dist
```

Test at least one installation on Linux, macOS, and Windows before promoting a
beta version to a stable release.
