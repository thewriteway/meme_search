#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "❌ $1" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local expected="$2"

    grep -Fq "$expected" "$file" || fail "Expected $file to contain: $expected"
}

assert_not_contains() {
    local file="$1"
    local unexpected="$2"

    if grep -Fq "$unexpected" "$file"; then
        fail "Expected $file not to contain: $unexpected"
    fi
}

assert_directory_exists() {
    local directory="$1"

    [ -d "$ROOT_DIR/$directory" ] || fail "Expected directory to exist: $directory"
}

validate_compose_file() {
    local compose_file="$1"
    local rendered_config
    rendered_config="$(mktemp)"
    trap 'rm -f "$rendered_config"' RETURN

    (
        cd "$ROOT_DIR"
        docker compose -f "$compose_file" config > "$rendered_config"
    )

    assert_not_contains "$ROOT_DIR/$compose_file" "version:"
    assert_contains "$rendered_config" "target: /var/lib/postgresql/data"
    assert_contains "$rendered_config" "type: volume"
    assert_contains "$rendered_config" "source: meme_search_db_data"
    assert_not_contains "$rendered_config" "meme_search/db_data/meme-search-db"
    assert_contains "$rendered_config" "target: /rails/public/memes/direct-uploads"
    assert_contains "$rendered_config" "target: /app/public/memes/direct-uploads"
    assert_contains "$rendered_config" "target: /app/db"
    assert_contains "$rendered_config" "target: /root/.cache/huggingface"
}

assert_directory_exists "meme_search/direct-uploads"
assert_directory_exists "meme_search/db_data/image_to_text_generator"
assert_directory_exists "meme_search/models"

validate_compose_file "docker-compose.yml"
validate_compose_file "docker-compose-local-build.yml"

echo "✓ Docker Compose persistence path tests passed"
