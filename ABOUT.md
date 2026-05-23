# 🐸 FroggyDocs Project Guide

## Overview

FroggyDocs is a cross-platform tool designed to auto-generate interactive API documentation from code annotations. It supports multiple programming languages (JavaScript, Python, Go, Ruby, etc.) and provides a modern web interface for viewing and testing API endpoints.

### Core Technologies
- **Language:** Dart (SDK ^3.11.5)
- **Frontend Framework:** [Jaspr](https://pub.dev/packages/jaspr) (Dart web framework)
- **HTTP Server:** [Shelf](https://pub.dev/packages/shelf)
- **CLI Utilities:** `package:args`, `package:watcher`
- **Specification:** OpenAPI 3.0.0

### Architecture
- **CLI (`bin/froggy_docs.dart`):** The entry point for commands like `serve` and `watch`.
- **Parser Engine (`lib/src/parser_engine.dart`):** Scans source files for comments starting with `@api` and other tags to build the OpenAPI specification.
- **Web Server (`lib/src/web_server.dart`):** Serves the generated documentation and handles API proxying for the "Try It Out" feature.
- **Frontend (`frontend/`):** A client-side Jaspr application that consumes the generated `froggy_docs.json` and renders the UI.

---

## Getting Started

### Prerequisites
- Dart SDK installed and configured.
- (Optional) Node.js/npm for global installation.
- (Optional) Docker for containerized deployment.

### Development Setup
1.  **Install dependencies:**
    ```bash
    dart pub get
    cd frontend && dart pub get
    ```

2.  **Run the CLI locally:**
    ```bash
    dart bin/froggy_docs.dart serve
    ```

3.  **Build the frontend:**
    ```bash
    cd frontend
    dart run build_runner build
    ```

### Testing
Run tests using the standard Dart test runner:
```bash
dart test
```

---

## Development Conventions

### Annotation Syntax
The parser scans for specific tags in comments. Supported languages use their standard comment prefixes (e.g., `//` for JS/Dart, `#` for Python).

| Tag | Description | Example |
|-----|-------------|---------|
| `@api` | Defines the method and path | `@api POST /api/users` |
| `@desc` | Brief description of the endpoint | `@desc Create a new user` |
| `@tag` | Groups endpoints in the UI | `@tag Users` |
| `@body` | Defines a request body field | `@body name string User's full name` |
| `@body-json` | Inline JSON schema for the body | `@body-json {"id": 1}` |
| `@auth` | Marks the endpoint as requiring authentication | `@auth` |

### Coding Standards
- Follow the [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style).
- Use `package:lints/recommended.yaml` for static analysis.
- Ensure all new logic is added to `lib/src/` and properly exported if necessary.
- Frontend components should be modular Jaspr components located in `frontend/lib/`.

---

## Deployment and Distribution

### npm
The project includes a `package.json` for distribution via npm. The main executable is linked to `bin/froggy-docs` (which may be a wrapper script or compiled binary in the distributed package).

### Docker
A `Dockerfile` is provided for containerization.
```bash
docker build -t froggy-docs .
docker run -p 8080:8080 froggy-docs
```

### Pub
Distributed as a Dart package on [pub.dev](https://pub.dev/packages/froggy_docs).

---

## Key Files
- `bin/froggy_docs.dart`: CLI entry point and command handling.
- `lib/src/parser_engine.dart`: Core logic for parsing annotations and generating OpenAPI JSON.
- `lib/src/web_server.dart`: Shelf-based server with proxy support.
- `frontend/lib/app.dart`: Main frontend logic and UI rendering.
- `frontend/web/froggy_docs.json`: The generated OpenAPI specification used by the frontend.
