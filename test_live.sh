#!/bin/bash
# test_live.sh — run the skink-postgres live integration test against a
# real PostgreSQL server in a podman container.
#
#   ./test_live.sh                # start postgres:16-alpine, run, stop
#   SKINK_PG_DSN=... ./test_live.sh   # against an existing server
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${POSTGRES_IMAGE:-docker.io/library/postgres:16-alpine}"
PORT="${PG_PORT:-15432}"
DSN="${SKINK_PG_DSN:-}"
CONTAINER=""

SKINK_HOME="${SKINK_HOME:-$HOME/.local/skink/std}"
SKINK_BIN="${SKINK:-$(command -v skink || echo "$HOME/.local/skink/bin/skink")}"

cleanup() {
    [ -n "$CONTAINER" ] && podman rm -f "$CONTAINER" >/dev/null 2>&1
    rm -f "$SCRIPT_DIR/.live_test_bin"
}
trap cleanup EXIT

if [ -z "$DSN" ]; then
    if ! command -v podman >/dev/null 2>&1; then
        echo "SKIP: podman not available and SKINK_PG_DSN unset"
        exit 0
    fi
    CONTAINER=$(podman run -d --rm \
        -e POSTGRES_PASSWORD=skinktest \
        -e POSTGRES_USER=skink \
        -e POSTGRES_DB=skinkdb \
        -p "127.0.0.1:$PORT:5432" "$IMAGE")
    echo "started postgres container $CONTAINER on :$PORT"
    # Wait for readiness.
    for i in $(seq 1 60); do
        if podman exec "$CONTAINER" pg_isready -U skink -d skinkdb >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done
    sleep 0.5
    DSN="postgres://skink:skinktest@127.0.0.1:$PORT/skinkdb"
fi

SKINK_HOME="$SKINK_HOME" "$SKINK_BIN" -o "$SCRIPT_DIR/.live_test_bin" "$SCRIPT_DIR/live_test.skink" || exit 1
SKINK_PG_DSN="$DSN" "$SCRIPT_DIR/.live_test_bin"
