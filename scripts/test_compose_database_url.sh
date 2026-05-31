#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered_config="$(mktemp)"
trap 'rm -f "$rendered_config"' EXIT

(
    cd "$ROOT_DIR"
    DB_PORT=15432 docker compose -f docker-compose-local-build.yml config > "$rendered_config"
)

if grep -Fq "meme-search-db:15432" "$rendered_config"; then
    echo "❌ DATABASE_URL used host DB_PORT for internal container traffic" >&2
    exit 1
fi

grep -Fq "DATABASE_URL: postgres://postgres:postgres@meme-search-db:5432/meme_search" "$rendered_config" || {
    echo "❌ DATABASE_URL must use the internal Postgres container port 5432" >&2
    exit 1
}

echo "✓ Docker Compose database URL tests passed"
