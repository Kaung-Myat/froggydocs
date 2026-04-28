# FroggyDocs Dockerfile
# Multi-stage build for smaller image

# Stage 1: Build
FROM dart:stable AS builder

WORKDIR /app

# Copy source
COPY . .
RUN dart pub get

# Compile the executable
RUN dart compile exe bin/froggy_docs.dart -o froggy-docs

# Stage 2: Runtime
FROM debian:stable-slim

# Install curl for healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy compiled binary from builder
COPY --from=builder /app/froggy-docs /usr/local/bin/froggy-docs

# Copy docs and static files
COPY frontend/deploy/web /app/frontend/web
COPY frontend/web/froggy_docs.json /app/frontend/web/froggy_docs.json

# Make executable
RUN chmod +x /usr/local/bin/froggy-docs

# Expose default port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

# Default command
CMD ["froggy-docs", "serve", "-h", "0.0.0.0"]

# Alternative commands:
# docker run -p 8080:8080 froggy-docs serve -p 8080
# docker run -p 3000:8080 froggy-docs serve -p 3000
# docker run -v $(pwd):/app froggy-docs serve