#!/usr/bin/env bash
# Recon — Environment Lifecycle Manager
# Manages isolated Docker Compose environments per branch/PR.
# No git worktrees — uses git archive to extract branch code into a temp build context.
#
# Usage:
#   recon-env.sh up     <id> <branch> <ui_port> <api_port> <db_port> [compose_file]
#   recon-env.sh dev    <ui_port> <api_port> <db_port> [compose_file]
#   recon-env.sh down   <id>
#   recon-env.sh status <id>
#   recon-env.sh list
#   recon-env.sh nuke
#   recon-env.sh ports  <count>
#
# Modes:
#   up:     Extract branch via git archive, start Docker Compose, wait for healthy
#   dev:    Start Docker Compose from current directory (no extraction needed)
#   down:   Stop containers, remove volumes, clean up extracted code
#   status: Check if an environment is running and healthy
#   list:   Show all active environments
#   nuke:   Tear down every environment
#   ports:  Print allocated port ranges for N parallel environments

set -euo pipefail

RECON_BASE="/tmp/recon-envs"
PROJECT_PREFIX="recon"

# ─── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[recon-env]${NC} $*"; }
ok()   { echo -e "${GREEN}[recon-env]${NC} $*"; }
warn() { echo -e "${YELLOW}[recon-env]${NC} $*"; }
err()  { echo -e "${RED}[recon-env]${NC} $*" >&2; }

# ─── Port Allocation ────────────────────────────────────────────────────────

allocate_ports() {
    local count="${1:?Usage: recon-env.sh ports <count>}"
    echo "=== Port Allocation for $count environments ==="
    echo ""
    printf "%-8s %-10s %-10s %-10s\n" "Index" "UI Port" "API Port" "DB Port"
    printf "%-8s %-10s %-10s %-10s\n" "-----" "-------" "--------" "-------"
    for i in $(seq 0 $((count - 1))); do
        printf "%-8s %-10s %-10s %-10s\n" "$i" "$((5180 + i))" "$((8010 + i))" "$((5442 + i))"
    done
}

# ─── Health Check ────────────────────────────────────────────────────────────

wait_for_healthy() {
    local url="$1"
    local name="$2"
    local timeout="${3:-120}"
    local interval=3
    local elapsed=0

    log "Waiting for $name at $url (timeout: ${timeout}s)..."

    while [ "$elapsed" -lt "$timeout" ]; do
        local status
        status=$(curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "000")

        if [ "$status" != "000" ] && [ "$status" != "502" ] && [ "$status" != "503" ]; then
            ok "$name is UP (HTTP $status) after ${elapsed}s"
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    err "$name failed to start within ${timeout}s"
    return 1
}

# ─── Find compose file ──────────────────────────────────────────────────────

find_compose_file() {
    local dir="$1"
    local hint="${2:-}"

    # Try the hint first
    if [ -n "$hint" ] && [ -f "$dir/$hint" ]; then
        echo "$hint"
        return 0
    fi

    # Try common names
    for name in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        if [ -f "$dir/$name" ]; then
            echo "$name"
            return 0
        fi
    done

    return 1
}

# ─── Start Docker Compose ───────────────────────────────────────────────────

start_compose() {
    local project_name="$1"
    local build_dir="$2"
    local compose_file="$3"
    local ui_port="$4"
    local api_port="$5"
    local db_port="$6"

    log "Starting Docker Compose (project: $project_name)..."

    export RECON_UI_PORT="$ui_port"
    export RECON_API_PORT="$api_port"
    export RECON_DB_PORT="$db_port"

    if docker compose \
        -p "$project_name" \
        -f "$build_dir/$compose_file" \
        up -d --build 2>&1; then
        ok "Docker Compose started"
        return 0
    else
        err "Docker Compose failed to start"
        return 1
    fi
}

# ─── Write metadata ─────────────────────────────────────────────────────────

write_metadata() {
    local meta_dir="$1"
    local id="$2"
    local branch="$3"
    local ui_port="$4"
    local api_port="$5"
    local db_port="$6"
    local project_name="$7"
    local compose_file="$8"
    local build_dir="$9"
    local ui_healthy="${10}"
    local api_healthy="${11}"

    mkdir -p "$meta_dir"
    cat > "${meta_dir}/env.meta" <<ENVEOF
ID=$id
BRANCH=$branch
UI_PORT=$ui_port
API_PORT=$api_port
DB_PORT=$db_port
PROJECT_NAME=$project_name
COMPOSE_FILE=$compose_file
BUILD_DIR=$build_dir
STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
UI_HEALTHY=$ui_healthy
API_HEALTHY=$api_healthy
ENVEOF
}

# ─── Up (per-PR / per-branch) ───────────────────────────────────────────────

cmd_up() {
    local id="${1:?Usage: recon-env.sh up <id> <branch> <ui_port> <api_port> <db_port> [compose_file]}"
    local branch="${2:?Missing branch name}"
    local ui_port="${3:?Missing UI port}"
    local api_port="${4:?Missing API port}"
    local db_port="${5:?Missing DB port}"
    local compose_hint="${6:-}"

    local project_name="${PROJECT_PREFIX}-${id}"
    local build_dir="${RECON_BASE}/${project_name}/src"
    local meta_dir="${RECON_BASE}/${project_name}"

    echo ""
    echo "=== Environment: ${id} ==="
    echo "  Branch:   $branch"
    echo "  UI port:  $ui_port"
    echo "  API port: $api_port"
    echo "  DB port:  $db_port"
    echo "  Project:  $project_name"
    echo ""

    mkdir -p "$RECON_BASE"

    # ── Step 1: Extract branch code via git archive ──────────────────────

    if [ -d "$build_dir" ]; then
        warn "Build dir already exists at $build_dir — removing and re-extracting"
        rm -rf "$build_dir"
    fi

    log "Extracting branch code via git archive..."

    git fetch origin "$branch" 2>/dev/null || true

    mkdir -p "$build_dir"

    # Try origin/<branch> first, then local <branch>
    if git archive "origin/$branch" 2>/dev/null | tar -x -C "$build_dir"; then
        ok "Extracted from origin/$branch"
    elif git archive "$branch" 2>/dev/null | tar -x -C "$build_dir"; then
        ok "Extracted from $branch"
    else
        err "Failed to extract branch: $branch"
        rm -rf "$meta_dir"
        return 1
    fi

    # ── Step 2: Find compose file ────────────────────────────────────────

    local compose_file
    if compose_file=$(find_compose_file "$build_dir" "$compose_hint"); then
        log "Found compose file: $compose_file"
    else
        warn "No docker-compose file found in $build_dir"
        warn "Claude should generate one based on the detected stack."
        echo ""
        echo "COMPOSE_NEEDED=true"
        echo "BUILD_DIR=$build_dir"
        echo "PROJECT_NAME=$project_name"
        return 2
    fi

    # ── Step 3: Start Docker Compose ─────────────────────────────────────

    if ! start_compose "$project_name" "$build_dir" "$compose_file" "$ui_port" "$api_port" "$db_port"; then
        return 1
    fi

    # ── Step 4: Health checks ────────────────────────────────────────────

    local ui_healthy=false
    local api_healthy=false

    wait_for_healthy "http://localhost:$ui_port" "UI (port $ui_port)" 120 && ui_healthy=true
    wait_for_healthy "http://localhost:$api_port" "API (port $api_port)" 120 && api_healthy=true

    # ── Step 5: Report ───────────────────────────────────────────────────

    echo ""
    echo "=== Environment Ready ==="
    echo "  ID:     $id ($branch)"
    echo "  UI:     http://localhost:$ui_port $([ "$ui_healthy" = true ] && echo "(healthy)" || echo "(NOT RESPONDING)")"
    echo "  API:    http://localhost:$api_port $([ "$api_healthy" = true ] && echo "(healthy)" || echo "(NOT RESPONDING)")"
    echo "  DB:     localhost:$db_port"
    echo ""

    write_metadata "$meta_dir" "$id" "$branch" "$ui_port" "$api_port" "$db_port" \
        "$project_name" "$compose_file" "$build_dir" "$ui_healthy" "$api_healthy"

    if [ "$ui_healthy" = false ] || [ "$api_healthy" = false ]; then
        warn "Some services are not healthy."
        return 3
    fi

    return 0
}

# ─── Dev (current directory, no extraction) ──────────────────────────────────

cmd_dev() {
    local ui_port="${1:?Usage: recon-env.sh dev <ui_port> <api_port> <db_port> [compose_file]}"
    local api_port="${2:?Missing API port}"
    local db_port="${3:?Missing DB port}"
    local compose_hint="${4:-}"

    local branch
    branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    local id="dev-${branch//\//-}"
    local project_name="${PROJECT_PREFIX}-${id}"
    local build_dir
    build_dir=$(pwd)
    local meta_dir="${RECON_BASE}/${project_name}"

    echo ""
    echo "=== Dev Environment ==="
    echo "  Branch:   $branch"
    echo "  Dir:      $build_dir"
    echo "  UI port:  $ui_port"
    echo "  API port: $api_port"
    echo "  DB port:  $db_port"
    echo "  Project:  $project_name"
    echo ""

    mkdir -p "$RECON_BASE"

    # ── Find compose file in current dir ─────────────────────────────────

    local compose_file
    if compose_file=$(find_compose_file "$build_dir" "$compose_hint"); then
        log "Found compose file: $compose_file"
    else
        warn "No docker-compose file found in $build_dir"
        warn "Claude should generate one based on the detected stack."
        echo ""
        echo "COMPOSE_NEEDED=true"
        echo "BUILD_DIR=$build_dir"
        echo "PROJECT_NAME=$project_name"
        return 2
    fi

    # ── Start Docker Compose ─────────────────────────────────────────────

    if ! start_compose "$project_name" "$build_dir" "$compose_file" "$ui_port" "$api_port" "$db_port"; then
        return 1
    fi

    # ── Health checks ────────────────────────────────────────────────────

    local ui_healthy=false
    local api_healthy=false

    wait_for_healthy "http://localhost:$ui_port" "UI (port $ui_port)" 120 && ui_healthy=true
    wait_for_healthy "http://localhost:$api_port" "API (port $api_port)" 120 && api_healthy=true

    # ── Report ───────────────────────────────────────────────────────────

    echo ""
    echo "=== Dev Environment Ready ==="
    echo "  Branch: $branch"
    echo "  UI:     http://localhost:$ui_port $([ "$ui_healthy" = true ] && echo "(healthy)" || echo "(NOT RESPONDING)")"
    echo "  API:    http://localhost:$api_port $([ "$api_healthy" = true ] && echo "(healthy)" || echo "(NOT RESPONDING)")"
    echo "  DB:     localhost:$db_port"
    echo ""

    write_metadata "$meta_dir" "$id" "$branch" "$ui_port" "$api_port" "$db_port" \
        "$project_name" "$compose_file" "$build_dir" "$ui_healthy" "$api_healthy"

    if [ "$ui_healthy" = false ] || [ "$api_healthy" = false ]; then
        warn "Some services are not healthy."
        return 3
    fi

    return 0
}

# ─── Down ────────────────────────────────────────────────────────────────────

cmd_down() {
    local id="${1:?Usage: recon-env.sh down <id>}"
    local project_name="${PROJECT_PREFIX}-${id}"
    local meta_dir="${RECON_BASE}/${project_name}"

    echo ""
    log "Tearing down environment: ${id}..."

    if [ -f "${meta_dir}/env.meta" ]; then
        source "${meta_dir}/env.meta"

        # Stop Docker Compose
        if [ -f "$BUILD_DIR/$COMPOSE_FILE" ]; then
            log "Stopping Docker Compose (project: $PROJECT_NAME)..."
            docker compose -p "$PROJECT_NAME" -f "$BUILD_DIR/$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
            ok "Docker Compose stopped"
        else
            docker compose -p "$PROJECT_NAME" down -v --remove-orphans 2>/dev/null || true
        fi

        # Kill orphan processes on ports (fallback)
        for port in "$UI_PORT" "$API_PORT" "$DB_PORT"; do
            local pids
            pids=$(lsof -ti:"$port" 2>/dev/null || true)
            if [ -n "$pids" ]; then
                echo "$pids" | xargs kill 2>/dev/null || true
                log "Killed processes on port $port"
            fi
        done
    else
        docker compose -p "$project_name" down -v --remove-orphans 2>/dev/null || true
    fi

    # Remove extracted source (but not if it's the user's actual working directory)
    if [ -d "$meta_dir" ] && echo "$meta_dir" | grep -q "/tmp/recon-envs/"; then
        rm -rf "$meta_dir"
        ok "Cleaned up $meta_dir"
    fi

    ok "Environment '${id}' fully cleaned up"
    echo ""
}

# ─── Status ──────────────────────────────────────────────────────────────────

cmd_status() {
    local id="${1:?Usage: recon-env.sh status <id>}"
    local project_name="${PROJECT_PREFIX}-${id}"
    local meta_dir="${RECON_BASE}/${project_name}"

    if [ ! -f "${meta_dir}/env.meta" ]; then
        err "No environment found: $id"
        return 1
    fi

    source "${meta_dir}/env.meta"

    local ui_status api_status
    ui_status=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$UI_PORT" 2>/dev/null || echo "000")
    api_status=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$API_PORT" 2>/dev/null || echo "000")

    echo ""
    echo "=== Environment: ${ID} ==="
    echo "  Branch:   $BRANCH"
    echo "  Started:  $STARTED_AT"
    echo "  UI:       http://localhost:$UI_PORT -> HTTP $ui_status $([ "$ui_status" != "000" ] && echo "(UP)" || echo "(DOWN)")"
    echo "  API:      http://localhost:$API_PORT -> HTTP $api_status $([ "$api_status" != "000" ] && echo "(UP)" || echo "(DOWN)")"
    echo "  DB:       localhost:$DB_PORT"
    echo ""

    docker compose -p "$PROJECT_NAME" ps 2>/dev/null || warn "Could not query Docker Compose"
    echo ""
}

# ─── List ────────────────────────────────────────────────────────────────────

cmd_list() {
    echo ""
    echo "=== Active Environments ==="
    echo ""

    if [ ! -d "$RECON_BASE" ]; then
        echo "  (none)"
        echo ""
        return 0
    fi

    local found=false
    for meta_dir in "$RECON_BASE"/${PROJECT_PREFIX}-*; do
        [ ! -d "$meta_dir" ] && continue
        [ ! -f "$meta_dir/env.meta" ] && continue
        found=true

        source "$meta_dir/env.meta"
        local ui_status
        ui_status=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$UI_PORT" 2>/dev/null || echo "000")
        local status_icon
        [ "$ui_status" != "000" ] && status_icon="${GREEN}UP${NC}" || status_icon="${RED}DOWN${NC}"

        printf "  %-20s  %-30s  UI=:%s  API=:%s  %b\n" \
            "$ID" "$BRANCH" "$UI_PORT" "$API_PORT" "$status_icon"
    done

    if [ "$found" = false ]; then
        echo "  (none)"
    fi

    echo ""
}

# ─── Nuke ────────────────────────────────────────────────────────────────────

cmd_nuke() {
    echo ""
    warn "Tearing down ALL environments..."
    echo ""

    if [ ! -d "$RECON_BASE" ]; then
        ok "No environments to clean up"
        return 0
    fi

    for meta_dir in "$RECON_BASE"/${PROJECT_PREFIX}-*; do
        [ ! -d "$meta_dir" ] && continue
        [ ! -f "$meta_dir/env.meta" ] && continue

        source "$meta_dir/env.meta"
        cmd_down "$ID" 2>/dev/null || true
    done

    rm -rf "$RECON_BASE"
    ok "All environments destroyed"
    echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────

cmd="${1:-help}"
shift || true

case "$cmd" in
    up)     cmd_up "$@" ;;
    dev)    cmd_dev "$@" ;;
    down)   cmd_down "$@" ;;
    status) cmd_status "$@" ;;
    list)   cmd_list ;;
    nuke)   cmd_nuke ;;
    ports)  allocate_ports "$@" ;;
    *)
        echo "Recon Environment Manager"
        echo ""
        echo "Usage:"
        echo "  recon-env.sh up     <id> <branch> <ui_port> <api_port> <db_port> [compose_file]"
        echo "  recon-env.sh dev    <ui_port> <api_port> <db_port> [compose_file]"
        echo "  recon-env.sh down   <id>"
        echo "  recon-env.sh status <id>"
        echo "  recon-env.sh list"
        echo "  recon-env.sh nuke"
        echo "  recon-env.sh ports  <count>"
        echo ""
        echo "Modes:"
        echo "  up   — Extract a branch via git archive, start isolated Docker env"
        echo "  dev  — Start Docker env from current directory (no extraction)"
        echo ""
        echo "Environment variables used by docker-compose.yml:"
        echo "  RECON_UI_PORT   — frontend port"
        echo "  RECON_API_PORT  — backend port"
        echo "  RECON_DB_PORT   — database port"
        echo ""
        echo "Exit codes:"
        echo "  0 — success"
        echo "  1 — error"
        echo "  2 — compose file needed (Claude should generate one)"
        echo "  3 — running but not fully healthy"
        ;;
esac
