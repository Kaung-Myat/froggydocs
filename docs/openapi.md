# OpenAPI input

FroggyDocs accepts OpenAPI 3.0.x and 3.1.x documents from a local JSON/YAML file or a running HTTP/HTTPS endpoint. Annotation scanning remains the default when no input source is selected.

## Local files

```bash
froggy-docs serve --spec ./openapi.yaml --proxy http://127.0.0.1:3000
froggy-docs watch --spec ./openapi.json
froggy-docs build --spec ./openapi.yaml --output ./dist/api-docs
```

While `serve` or `watch` runs, FroggyDocs watches the containing directory so specifications replaced atomically by another generator are reloaded. A malformed replacement is reported and the last valid generated specification remains available.

## Remote specifications

```bash
froggy-docs serve \
  --spec-url http://127.0.0.1:8000/openapi.json \
  --proxy http://127.0.0.1:8000
```

Remote specifications are polled every 10 seconds by default. Change the interval with `--spec-poll-interval`; the minimum is two seconds.

```bash
froggy-docs serve \
  --spec-url https://staging-api.example.com/openapi.json \
  --spec-poll-interval 30
```

For an authenticated endpoint, place a single request header in an environment variable. Do not put bearer tokens directly in command arguments.

```bash
export FROGGY_OPENAPI_HEADER='Authorization: Bearer your-token'
froggy-docs serve \
  --spec-url https://api.example.com/openapi.json \
  --spec-header-env FROGGY_OPENAPI_HEADER
```

## Project configuration

The same input can be selected in `froggy_docs.yaml`:

```yaml
input:
  spec: ./openapi.yaml
  # specUrl: https://api.example.com/openapi.json
  # specHeaderEnv: FROGGY_OPENAPI_HEADER
  pollIntervalSeconds: 10
```

Define only `spec` or `specUrl`, never both. An explicit CLI input overrides the configured input. An explicit `--project` selects annotation mode.

## Framework examples

FastAPI exposes `/openapi.json` by default:

```bash
froggy-docs serve --spec-url http://127.0.0.1:8000/openapi.json --proxy http://127.0.0.1:8000
```

Spring Boot with springdoc-openapi commonly exposes `/v3/api-docs`:

```bash
froggy-docs serve --spec-url http://127.0.0.1:8080/v3/api-docs --proxy http://127.0.0.1:8080
```

Go and Express generators can write a file consumed independently:

```bash
froggy-docs build --spec ./docs/openapi.yaml --output ./public/api-docs
```

## Validation and normalization

FroggyDocs checks the root object, OpenAPI version, `info.title`, `info.version`, `paths`, path names, operation objects, and `$ref` targets. Internal JSON Pointer references are expanded for UI compatibility. External `$ref` documents and Swagger 2.0 are rejected with a clear message in this release.

Remote downloads allow only HTTP/HTTPS, follow at most five redirects, time out after 20 seconds, and are limited to 10 MB. Credentials embedded in a URL are rejected. Production specification endpoints should use HTTPS.

Configured `servers` replace imported servers when present, which allows FroggyDocs environment safety controls to be applied. Without configured servers, the document's original OpenAPI servers are preserved.
