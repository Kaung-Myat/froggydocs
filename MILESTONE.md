# 🐸 FroggyDocs Milestone

## Date: May 1, 2026

---

## 🎯 Project Overview

**FroggyDocs** - Auto-generate API documentation from code annotations. Works with any programming language.

---

## ✅ Completed Features

### Core Parser Engine
- [x] Parse `@api` annotation for endpoint definitions
- [x] Parse `@desc` for descriptions  
- [x] Parse `@tag` for grouping/categories
- [x] Parse `@body` for request body fields
- [x] Parse `@body-json` for inline JSON
- [x] Parse `@body-file` for external JSON files
- [x] Parse `@auth` for authentication requirements

### Language Support
- [x] JavaScript/TypeScript (.js, .ts, .jsx, .tsx)
- [x] Python (.py)
- [x] Ruby (.rb)
- [x] Go (.go)
- [x] Rust (.rs)
- [x] Dart (.dart)
- [x] Java/Kotlin (.java, .kt)
- [x] PHP (.php)
- [x] C# (.cs)
- [x] C/C++ (.c, .cpp, .h)

### Web Server
- [x] Built-in HTTP server with Shelf
- [x] Live documentation at `/`
- [x] Serves froggy_docs.json at `/froggy_docs.json`
- [x] Static file serving (CSS, JS)
- [x] Mock API endpoints for Try It Out testing
- [x] **NEW** Proxy support for forwarding API requests to backend server (`--proxy` option)

### Frontend UI
- [x] Sidebar with tag groups (collapsible)
- [x] Search bar (search by tag name or endpoint path)
- [x] Theme toggle (light/dark mode)
- [x] Authorization header input
- [x] Request body form with input fields
- [x] "Try It Out" button with live API calls
- [x] Response display on page
- [x] Method badges (color-coded GET/POST/PUT/DELETE)
- [x] **CHANGED** Replaced Jaspr (Dart) with vanilla JavaScript for better compatibility

### Deployment
- [x] Standalone executable (dart compile exe)
- [x] package.json for npm publishing
- [x] install.sh script
- [x] Dockerfile
- [x] .froggyrc.example config
- [x] GitHub Actions CI workflow
- [x] Published to npm as `froggy-docs`

---

## 📂 Project Structure

```
froggy_docs/
├── bin/froggy_docs.dart          # CLI entrypoint
├── bin/froggy-docs               # Compiled executable
├── lib/
│   └── src/
│       ├── parser_engine.dart    # Annotation parser
│       ├── watcher_engine.dart   # File watcher
│       └── web_server.dart       # HTTP server + proxy
├── frontend/
│   ├── web/
│   │   ├── index.html           # Main UI
│   │   ├── app.js               # JavaScript frontend
│   │   ├── styles.css           # Styling
│   │   └── froggy_docs.json     # Generated docs
│   └── pubspec.yaml
├── docs/
│   └── annotations.md           # Full annotation guide
├── package.json                 # npm package config
├── package.js                   # npm wrapper
├── install.sh                   # Shell installer
├── Dockerfile                   # Docker image
├── .froggyrc.example            # Config example
├── pubspec.yaml                 # Dart dependencies
└── README.md                    # Documentation
```

---

## 🚀 Usage

```bash
# Via npm
npm install -g froggy-docs
froggy-docs serve

# With proxy to backend API (e.g., Express on port 3000)
froggy-docs serve --proxy http://localhost:3000

# Via Docker
docker run -p 8080:8080 froggy-docs

# Via binary
./froggy-docs serve -p 8080 --proxy http://localhost:3000
```

---

## 📝 Annotation Syntax

```javascript
// @api POST /api/users
// @tag Users
// @tag Auth
// @desc Create a new user
// @body name string User's full name
// @body email string User's email
// @auth
app.post('/api/users', handler);
```

---

## 🔄 What's Next (Future Ideas)

- [ ] VS Code Extension
- [ ] GitHub Template repository
- [ ] Support for response examples
- [ ] Rate limiting documentation
- [ ] Multi-language search
- [ ] Custom themes
- [ ] Export to Markdown/HTML static files

---

## 🙏 Acknowledgments

Built with:
- [Shelf](https://pub.dev/packages/shelf) - HTTP server
- [Watcher](https://pub.dev/packages/watcher) - File watching

---

## 📦 Latest Version

**Version: 1.1.1**

npm: `npm install -g froggy-docs`
Docker: `docker run -p 8080:8080 froggy-docs`
GitHub: [Releases](https://github.com/Kaung-Myat/froggydocs/releases)