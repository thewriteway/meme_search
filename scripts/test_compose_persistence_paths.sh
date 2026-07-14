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
    assert_contains "$rendered_config" "type: bind"
    assert_contains "$rendered_config" "meme_search/db_data/meme-search-db"
    assert_contains "$rendered_config" "meme_search_uploads_setup"
    assert_contains "$rendered_config" "chown -R 1000:1000 /direct-uploads"
    assert_contains "$rendered_config" "condition: service_completed_successfully"
    assert_contains "$rendered_config" "target: /direct-uploads"
    assert_contains "$rendered_config" "target: /rails/public/memes/direct-uploads"
    assert_contains "$rendered_config" "target: /app/public/memes/direct-uploads"
    assert_contains "$rendered_config" "target: /app/db"
    assert_contains "$rendered_config" "target: /root/.cache/huggingface"
    assert_contains "$rendered_config" "meme_search/direct-uploads"
    assert_contains "$rendered_config" "meme_search/db_data/image_to_text_generator"
    assert_contains "$rendered_config" "meme_search/models"
    assert_contains "$rendered_config" "host_ip: 127.0.0.1"
}

validate_path_overrides() {
    local compose_file="$1"
    local rendered_config
    rendered_config="$(mktemp)"
    trap 'rm -f "$rendered_config"' RETURN

    (
        cd "$ROOT_DIR"
        MEME_SEARCH_DB_PATH=/volume1/docker/meme-search/db \
        MEME_SEARCH_DIRECT_UPLOADS_PATH=/volume1/docker/meme-search/direct-uploads \
        MEME_SEARCH_GENERATOR_DB_PATH=/volume1/docker/meme-search/image-to-text-db \
        MEME_SEARCH_MODELS_PATH=/volume1/docker/meme-search/models \
            docker compose -f "$compose_file" config > "$rendered_config"
    )

    assert_contains "$rendered_config" "source: /volume1/docker/meme-search/db"
    assert_contains "$rendered_config" "source: /volume1/docker/meme-search/direct-uploads"
    assert_contains "$rendered_config" "source: /volume1/docker/meme-search/image-to-text-db"
    assert_contains "$rendered_config" "source: /volume1/docker/meme-search/models"
}

validate_bind_address_override() {
    local compose_file="$1"
    local rendered_config
    rendered_config="$(mktemp)"
    trap 'rm -f "$rendered_config"' RETURN

    (
        cd "$ROOT_DIR"
        APP_BIND_ADDRESS=0.0.0.0 docker compose -f "$compose_file" config > "$rendered_config"
    )

    assert_contains "$rendered_config" "host_ip: 0.0.0.0"
}

assert_directory_exists "meme_search/direct-uploads"
assert_directory_exists "meme_search/db_data/image_to_text_generator"
assert_directory_exists "meme_search/models"

git check-ignore --quiet "$ROOT_DIR/meme_search/direct-uploads/example.png" || fail "Expected direct upload files to be ignored"
git check-ignore --quiet "$ROOT_DIR/meme_search/db_data/image_to_text_generator/state.json" || fail "Expected generator runtime files to be ignored"
git check-ignore --quiet "$ROOT_DIR/meme_search/models/config.json" || fail "Expected model cache files to be ignored"

validate_compose_file "docker-compose.yml"
validate_compose_file "docker-compose-local-build.yml"
validate_path_overrides "docker-compose.yml"
validate_path_overrides "docker-compose-local-build.yml"
validate_bind_address_override "docker-compose.yml"
validate_bind_address_override "docker-compose-local-build.yml"

echo "✓ Docker Compose persistence path tests passed"
