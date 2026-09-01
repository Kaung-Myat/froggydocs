# Deploying FroggyDocs for a team

FroggyDocs can be exported as a self-contained static site and hosted under a
path such as `https://api.example.com/docs/api/`.

## Configure the documentation

Copy `froggy_docs.example.yaml` to the API project as `froggy_docs.yaml`, then
set the project metadata, deployment base path, and API environments.

Production environments should normally use `readOnly: true`. If mutations
are required, use `confirmMutations: true` so POST, PUT, PATCH, and DELETE
requests require an explicit confirmation.

## Build

From the FroggyDocs package:

```bash
dart run bin/froggy_docs.dart build \
  --project ../your-api \
  --output dist
```

The output directory contains all required deployment files:

```text
dist/
├── index.html
├── app.js
├── styles.css
├── token_storage.js
├── favicon.ico
└── froggy_docs.json
```

## Nginx subpath hosting

Copy the generated files to `/var/www/api-docs/`, then configure Nginx:

```nginx
location = /docs/api {
    return 301 /docs/api/;
}

location /docs/api/ {
    alias /var/www/api-docs/;
    try_files $uri $uri/ /docs/api/index.html;
}
```

The trailing slash is important because FroggyDocs resolves its assets and
specification relative to the documentation URL.

## Protect internal documentation

Documentation access and API authorization are separate controls. Protect the
documentation with the company's SSO, VPN, Cloudflare Access, or reverse-proxy
authentication. Do not put shared passwords or API tokens in the static build.

For a small internal deployment, Nginx Basic Authentication can be used:

```nginx
location /docs/api/ {
    auth_basic "Internal API Documentation";
    auth_basic_user_file /etc/nginx/api-docs.htpasswd;

    alias /var/www/api-docs/;
    try_files $uri $uri/ /docs/api/index.html;
}
```

Use HTTPS for every deployed environment. API servers on another origin must
allow the documentation origin through their CORS policy.

## CI/CD outline

Run tests, build FroggyDocs, and publish the static directory whenever the API
contract changes:

```text
API source push
  -> tests and analysis
  -> FroggyDocs build
  -> publish dist/ to /docs/api/
```

Keep production documentation free of real customer data, permanent admin
tokens, database credentials, and other secrets.
