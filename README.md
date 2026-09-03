# FroggyDocs

Language-agnostic API documentation generated from source annotations. FroggyDocs scans your project, produces an OpenAPI 3.0 specification, and serves an interactive documentation UI with request testing, live reload, backend proxying, and static site export.

**Current version:** `1.2.0-beta.2`

[![Pub](https://img.shields.io/pub/v/froggy_docs.svg)](https://pub.dev/package/froggy_docs)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![npm](https://img.shields.io/npm/v/froggy-docs/beta.svg)](https://www.npmjs.com/package/froggy-docs)

Repository: [Kaung-Myat/froggydocs](https://github.com/Kaung-Myat/froggydocs)

---

## Features

- Annotation-driven OpenAPI 3.0 generation from comments in many languages
- Interactive documentation UI with try-it-out requests
- Live regeneration while source files change (`serve` and `watch`)
- Optional reverse proxy from the docs server to a local or remote API
- Multiple API environments with read-only and mutation-confirmation controls
- Multipart and file upload testing in the UI
- Encrypted browser-side authorization token storage
- Static site builds for Nginx or other static hosting, including subpaths

---

## Installation

### npm (recommended for most users)

The npm package installs a Node.js launcher that downloads and verifies the matching native binary from GitHub Releases.

```bash
npm install -g froggy-docs@beta
froggy-docs --version
froggy-docs install   # optional; downloads the binary early
```

Requires Node.js 18 or later. Supported binaries: Linux x64/arm64, macOS x64/arm64, Windows x64.

### Dart (development / from source)

```bash
git clone https://github.com/Kaung-Myat/froggydocs.git
cd froggydocs
dart pub get
dart run bin/froggy_docs.dart --help
```

### Docker

```bash
docker build -t froggy-docs .
docker run --rm -p 8080:8080 -v "$(pwd):/app" -w /app froggy-docs serve --project .
```

### Standalone binaries

Download platform assets from the [GitHub Releases](https://github.com/Kaung-Myat/froggydocs/releases) page for the matching version tag (for example `v1.2.0-beta.2`).

---

## Quick start

### 1. Annotate an endpoint

```javascript
// @api POST /api/users
// @tag Users
// @desc Create a new user
// @body name string User full name
// @body email string User email
// @auth
app.post('/api/users', async (req, res) => {
  // handler
});
```

### 2. Add project configuration (optional but recommended)

Copy [`froggy_docs.example.yaml`](froggy_docs.example.yaml) into your API project as `froggy_docs.yaml`.

### 3. Serve documentation

```bash
# From an API project directory
froggy-docs serve

# Or point at another project and proxy Try It Out requests to Express
froggy-docs serve --project ./my-api --proxy http://127.0.0.1:3000
```

Open `http://localhost:8080` in a browser.

---

## CLI

| Command | Description |
|---------|-------------|
| `serve` | Generate the specification, start the docs server, and watch for changes |
| `watch` | Regenerate the specification on file changes without serving the UI |
| `build` | Generate a self-contained static documentation site |
| `install` | npm launcher only: download and verify the native binary for this version |

### Options

| Option | Description |
|--------|-------------|
| `-p, --port <port>` | Docs server port (default: `8080`, or `server.port` from config) |
| `-x, --proxy <url>` | Forward `/api/*` and `/uploads/*` to this backend base URL |
| `-o, --output <path>` | Specification JSON path, or build output directory when the path does not end in `.json` |
| `--dist <path>` | Static build output directory (default: `dist`, or `docs.outputDirectory`) |
| `--base-path <path>` | Documentation URL base path (example: `/docs/api/`) |
| `--ignore <glob>` | Glob pattern excluded from watching |
| `--project <path>` | API project directory to scan (default: current directory) |
| `-h, --help` | Show help |

### Examples

```bash
froggy-docs serve --project ../my-api --proxy http://127.0.0.1:3000
froggy-docs serve --project ../my-api --base-path /docs/api/
froggy-docs watch --project ../my-api
froggy-docs build --project ../my-api --output dist
froggy-docs build --project ../my-api --dist public/docs/api
```

From a Dart checkout:

```bash
dart run bin/froggy_docs.dart serve --project ../express-mvc-starter --proxy http://127.0.0.1:3000
```

### Proxy notes

When `serve` is started with `--proxy` (or `server.proxy` in `froggy_docs.yaml`), the docs UI can use a relative environment URL such as `/`. Browser requests go to FroggyDocs, which forwards them to the backend.

If `http://localhost:3000` fails to connect from the proxy while the API is running, try `http://127.0.0.1:3000`. On some systems `localhost` resolves to IPv6 (`::1`) while the API process listens only on IPv4.

The docs server currently binds to `localhost`. Access it on the same machine via `http://localhost:<port>`.

---

## Configuration

Create `froggy_docs.yaml` in the API project root. Legacy `.froggyrc` JSON files are still loaded when YAML is absent.

```yaml
project:
  title: HR Mobile API
  version: 1.0.0
  description: Internal API reference for backend, mobile, web, and QA teams.

docs:
  basePath: /docs/api/
  outputDirectory: dist
  defaultEnvironment: Staging

server:
  port: 8080
  proxy: http://127.0.0.1:3000

output:
  file: frontend/web/froggy_docs.json

servers:
  - name: Local proxy
    url: /
    environment: development

  - name: Staging
    url: https://staging-api.example.com
    environment: staging

  - name: Production
    url: https://api.example.com
    environment: production
    readOnly: true
    confirmMutations: true
```

See [`froggy_docs.example.yaml`](froggy_docs.example.yaml) for a complete example.

Production environments should normally set `readOnly: true`. If mutations are allowed, set `confirmMutations: true` so POST, PUT, PATCH, and DELETE require confirmation in the UI.

---

## Annotations

| Annotation | Purpose | Example |
|------------|---------|---------|
| `@api` | HTTP method and path (required) | `@api GET /users` |
| `@desc` | Endpoint summary | `@desc List users` |
| `@tag` | UI grouping (repeatable) | `@tag Users` |
| `@body` | JSON body field | `@body name string Full name` |
| `@body-json` | Inline JSON body example/schema | `@body-json {"name":"Ada"}` |
| `@body-file` | Body schema from a JSON file | `@body-file ./schemas/user.json` |
| `@file` | Multipart file field | `@file avatar binary Profile image` |
| `@query` | Query parameter | `@query limit number Max rows` |
| `@header` | Request header | `@header X-Request-ID string Trace id` |
| `@auth` | Requires authentication | `@auth` |
| `@response` | Response status and type | `@response 200 object User payload` |
| `@response-json` | Inline JSON response example | `@response-json 200 {"id":"1"}` |

Full reference: [docs/annotations.md](docs/annotations.md)

---

## Supported languages

| Language | Extensions | Comment prefix |
|----------|------------|----------------|
| JavaScript / TypeScript | `.js`, `.ts`, `.jsx`, `.tsx` | `//` |
| Dart | `.dart` | `//` |
| Python | `.py` | `#` |
| Ruby | `.rb` | `#` |
| Go | `.go` | `//` |
| Rust | `.rs` | `//` |
| Java / Kotlin / Scala | `.java`, `.kt`, `.scala` | `//` |
| PHP | `.php` | `//` |
| C# | `.cs` | `//` |
| C / C++ | `.c`, `.cpp`, `.h`, `.hpp` | `//` |

The scanner skips common non-source trees such as `node_modules/`, `.git/`, `.dart_tool/`, and `frontend/`.

---

## Static deployment

```bash
froggy-docs build --project ../your-api --output dist
```

The output directory includes `index.html`, UI assets, `token_storage.js`, and `froggy_docs.json`. Host it at `/` or at a configured base path such as `/docs/api/`.

See [DEPLOYMENT.md](DEPLOYMENT.md) for Nginx subpath hosting, access control, CORS, and CI/CD guidance.

---

## Development

Prerequisites: Dart SDK matching `pubspec.yaml` (`^3.11.5`).

```bash
dart pub get
cd frontend && dart pub get && cd ..

dart analyze
dart test
npm test
npm run verify-version
```

Run the CLI against a fixture API (for example the sibling Express starter):

```bash
dart run bin/froggy_docs.dart serve --project ../express-mvc-starter --proxy http://127.0.0.1:3000
```

Release process for maintainers: [RELEASE.md](RELEASE.md). Project internals overview: [ABOUT.md](ABOUT.md).

---

## Architecture (overview)

| Component | Role |
|-----------|------|
| `bin/froggy_docs.dart` | CLI entrypoint |
| `lib/src/parser_engine.dart` | Annotation parsing and OpenAPI generation |
| `lib/src/web_server.dart` | Shelf HTTP server, static assets, API/media proxy |
| `lib/src/watcher_engine.dart` | File watching and regeneration |
| `lib/src/froggy_config.dart` | YAML / legacy JSON configuration |
| `frontend/web/` | Documentation UI assets consumed by `serve` and `build` |
| `package.js` | npm launcher with checksum-verified binary install |

---

## Contributing

1. Fork the repository.
2. Create a feature branch.
3. Run `dart analyze`, `dart test`, and `npm test` before opening a pull request.
4. Keep `package.json`, `pubspec.yaml`, and `lib/src/version.dart` synchronized when changing the version.

---

## License

MIT License. See [LICENSE](LICENSE).

---

## Acknowledgments

- [Shelf](https://pub.dev/packages/shelf) — HTTP server
- [Watcher](https://pub.dev/packages/watcher) — filesystem watching
- [Jaspr](https://pub.dev/packages/jaspr) — frontend tooling used to build the documentation UI
