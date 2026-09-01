# 🐸 FroggyDocs

> Auto-generate API documentation from code annotations. Works with any programming language.

[![Pub](https://img.shields.io/pub/v/froggy_docs.svg)](https://pub.dev/package/froggy_docs)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-ready-blue.svg)](https://docker.com)

---

## ✨ Features

- 📝 **Easy Annotations** - Add comments to your API code, no config needed
- 🌐 **Universal** - Works with any language (JavaScript, Python, Go, Ruby, etc.)
- 🎨 **Beautiful UI** - Interactive API docs with "Try It Out" functionality
- 🔄 **Live Reload** - Auto-regenerates docs when code changes
- 📦 **Multiple Outputs** - npm, Docker, GitHub Template
- 🔒 **OpenAPI 3.0** - Industry-standard specification

---

## 🚀 Quick Start

### Via npm (Beta)
```bash
npm install -g froggy-docs@beta
froggy-docs serve
```

### Via Docker
```bash
docker run -p 8080:8080 froggy-docs
```

### Via Dart
```bash
dart pub global activate froggy_docs
froggy_docs serve
```

---

## 💻 Usage

### 1. Add Annotations to Your Code

```javascript
// @api POST /api/users
// @tag Users
// @tag Auth
// @desc Create a new user
// @body name string User's full name
// @body email string User's email
// @auth
app.post('/api/users', async (req, res) => {
  // Your API logic here
});
```

### 2. Run the Documentation Server

```bash
# Default (localhost:8080)
froggy-docs serve

# Custom port
froggy-docs serve -p 3000

# Network accessible
froggy-docs serve -h 0.0.0.0 -p 8080

# Watch mode (no server)
froggy-docs watch
```

### 3. Open in Browser

```
http://localhost:8080
```

---

## 📖 Annotation Reference

| Annotation | Description | Example |
|------------|-------------|---------|
| `@api` | Define endpoint | `@api GET /users` |
| `@desc` | Description | `@desc Get all users` |
| `@tag` | Category | `@tag Users` |
| `@body` | Request body field | `@body name string User's name` |
| `@body-json` | Inline JSON schema | `@body-json {...}` |
| `@body-file` | From JSON file | `@body-file ./schema.json` |
| `@auth` | Requires auth | `@auth` |

**Full guide:** [docs/annotations.md](docs/annotations.md)

---

## 🐳 Docker

### Build
```bash
docker build -t froggy-docs .
```

### Run
```bash
# Default
docker run -p 8080:8080 froggy-docs

# Custom port
docker run -p 3000:8080 froggy-docs serve -p 3000

# Mount project
docker run -v $(pwd):/app -p 8080:8080 froggy-docs
```

### Docker Compose
```yaml
version: '3'
services:
  froggy-docs:
    build: .
    ports:
      - "8080:8080"
    volumes:
      - .:/app
    command: serve -h 0.0.0.0
```

---

## ⚙️ Configuration

Create `froggy_docs.yaml` in the API project root. Legacy `.froggyrc` JSON
files remain supported when a YAML configuration is not present.

```yaml
project:
  title: HR Mobile API
  version: 1.0.0

docs:
  basePath: /docs/api/
  outputDirectory: dist
  defaultEnvironment: Staging

servers:
  - name: Staging
    url: https://staging-api.example.com
    environment: staging

  - name: Production
    url: https://api.example.com
    environment: production
    readOnly: true
    confirmMutations: true
```

See [`froggy_docs.example.yaml`](froggy_docs.example.yaml) for the complete
configuration.

## Static deployment

Generate a self-contained site:

```bash
froggy_docs build --project ../your-api --output dist
```

The resulting directory contains `index.html`, UI assets, encrypted token
storage support, and `froggy_docs.json`. It can be hosted at `/` or at the
configured subpath such as `/docs/api/`.

See [DEPLOYMENT.md](DEPLOYMENT.md) for Nginx configuration, access control,
production safety, and a CI/CD outline.

---

## 🌐 Supported Languages

| Language | Extensions | Comment |
|----------|------------|----------|
| JavaScript/TypeScript | .js, .ts, .jsx, .tsx | `//` |
| Python | .py | `#` |
| Ruby | .rb | `#` |
| Go | .go | `//` |
| Rust | .rs | `//` |
| Dart | .dart | `//` |
| Java/Kotlin | .java, .kt | `//` |
| PHP | .php | `//` |
| C# | .cs | `//` |
| C/C++ | .c, .cpp, .h | `//` |

---

## 📦 Installation Options

### npm beta
```bash
npm install -g froggy-docs@beta
```

### pip
```bash
pip install froggy-docs
```

### Docker
```bash
docker run -p 8080:8080 froggy-docs
```

### Standalone Binary
Download from [Releases](https://github.com/yourusername/froggy-docs/releases)

---

## 🤝 Contributing

1. Fork the repo
2. Create your branch (`git checkout -b feature/amazing`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing`)
5. Open a Pull Request

---

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- [Shelf](https://pub.dev/packages/shelf) - HTTP server
- [Watcher](https://pub.dev/packages/watcher) - File watching
- [Jaspr](https://pub.dev/packages/jaspr) - Web framework
