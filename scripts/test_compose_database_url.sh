#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered_configs=()
trap 'rm -f "${rendered_configs[@]}"' EXIT

for compose_file in docker-compose.yml docker-compose-local-build.yml; do
    rendered_config="$(mktemp)"
    rendered_configs+=("$rendered_config")

    (
        cd "$ROOT_DIR"
        DB_PORT=15432 docker compose -f "$compose_file" config > "$rendered_config"
    )

    if grep -Fq "meme-search-db:15432" "$rendered_config"; then
        echo "❌ $compose_file DATABASE_URL used DB_PORT for internal container traffic" >&2
        exit 1
    fi

    grep -Fq "DATABASE_URL: postgres://postgres:postgres@meme-search-db:5432/meme_search" "$rendered_config" || {
        echo "❌ $compose_file DATABASE_URL must use the internal Postgres container port 5432" >&2
        exit 1
    }
done

echo "✓ Docker Compose database URL tests passed"
