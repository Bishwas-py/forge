#!/usr/bin/env bash
# Recon — Environment Lifecycle Manager
# Manages isolated per-PR environments using git worktrees + Docker Compose.
#
# Usage:
#   recon-env.sh up   <pr_number> <branch> <ui_port> <api_port> <db_port> [compose_file]
#   recon-env.sh down <pr_number>
#   recon-env.sh status <pr_number>
#   recon-env.sh list
#   recon-env.sh nuke                  # tear down ALL recon environments
#   recon-env.sh ports <count>         # allocate port ranges for N PRs
#
# The script:
#   up:     Creates a git worktree, starts Docker Compose with isolated ports, waits for healthy
#   down:   Stops containers, removes volumes, cleans up worktree
#   status: Checks if an environment is running and healthy
#   list:   Shows all active recon environments
#   nuke:   Tears down every recon environment
#   ports:  Prints allocated port ranges for N parallel PRs

set -euo pipefail

RECON_BASE="/tmp/recon-envs"
PROJECT_PREFIX="recon-pr"

# ─── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[recon]${NC} $*"; }
ok()   { echo -e "${GREEN}[recon]${NC} $*"; }
warn() { echo -e "${YELLOW}[recon]${NC} $*"; }
err()  { echo -e "${RED}[recon]${NC} $*" >&2; }

# ─── Port Allocation ────────────────────────────────────────────────────────

allocate_ports() {
    local count="${1:?Usage: recon-env.sh ports <count>}"
    echo "=== Port Allocation for $count PRs ==="
    echo ""
    printf "%-8s %-10s %-10s %-10s\n" "Index" "UI Port" "API Port" "DB Port"
    printf "%-8s %-10s %-10s %-10s\n" "-----" "-------" "--------" "-------"
    for i in $(seq 0 $((count - 1))); do
        local ui_port=$((5180 + i))
        local api_port=$((8010 + i))
        local db_port=$((5442 + i))
        printf "%-8s %-10s %-10s %-10s\n" "$i" "$ui_port" "$api_port" "$db_port"
    done
}

# ─── Health Check ────────────────────────────────────────────────────────────

wait_for_healthy() {
    local url="$1"
    local name="$2"
    local timeout="${3:-120}"  # seconds
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

# ─── Up ──────────────────────────────────────────────────────────────────────

cmd_up() {
    local pr_number="${1:?Usage: recon-env.sh up <pr_number> <branch> <ui_port> <api_port> <db_port> [compose_file]}"
    local branch="${2:?Missing branch name}"
    local ui_port="${3:?Missing UI port}"
    local api_port="${4:?Missing API port}"
    local db_port="${5:?Missing DB port}"
    local compose_file="${6:-docker-compose.yml}"

    local project_name="${PROJECT_PREFIX}-${pr_number}"
    local worktree_dir="${RECON_BASE}/${project_name}"
    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

    echo ""
    echo "=== Recon Environment: PR #${pr_number} ==="
    echo "  Branch:     $branch"
    echo "  Worktree:   $worktree_dir"
    echo "  UI port:    $ui_port"
    echo "  API port:   $api_port"
    echo "  DB port:    $db_port"
    echo "  Compose:    $compose_file"
    echo "  Project:    $project_name"
    echo ""

    # Create base directory
    mkdir -p "$RECON_BASE"

    # ── Step 1: Create worktree ──────────────────────────────────────────

    if [ -d "$worktree_dir" ]; then
        warn "Worktree already exists at $worktree_dir — reusing"
    else
        log "Creating git worktree..."

        # Fetch the branch if it's a remote ref
        git fetch origin "$branch" 2>/dev/null || true

        if git worktree add "$worktree_dir" "origin/$branch" 2>/dev/null; then
            ok "Worktree created from origin/$branch"
        elif git worktree add "$worktree_dir" "$branch" 2>/dev/null; then
            ok "Worktree created from $branch"
        else
            err "Failed to create worktree for branch: $branch"
            return 1
        fi
    fi

    # ── Step 2: Check for compose file ───────────────────────────────────

    local compose_path="$worktree_dir/$compose_file"
    if [ ! -f "$compose_path" ]; then
        # Try common alternatives
        for alt in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
            if [ -f "$worktree_dir/$alt" ]; then
                compose_file="$alt"
                compose_path="$worktree_dir/$alt"
                log "Found compose file: $alt"
                break
            fi
        done
    fi

    if [ ! -f "$compose_path" ]; then
        warn "No docker-compose file found at $worktree_dir"
        warn "Claude should generate one based on the detected stack."
        warn "Expected location: $compose_path"
        echo ""
        echo "COMPOSE_NEEDED=true"
        echo "WORKTREE_DIR=$worktree_dir"
        echo "PROJECT_NAME=$project_name"
        return 2  # Special exit code: worktree ready, needs compose file
    fi

    # ── Step 3: Start Docker Compose ─────────────────────────────────────

    log "Starting Docker Compose (project: $project_name)..."

    # Export port environment variables for the compose file to use
    export RECON_UI_PORT="$ui_port"
    export RECON_API_PORT="$api_port"
    export RECON_DB_PORT="$db_port"

    if docker compose \
        -p "$project_name" \
        -f "$compose_path" \
        up -d --build 2>&1; then
        ok "Docker Compose started"
    else
        err "Docker Compose failed to start"
        return 1
    fi

    # ── Step 4: Health checks ────────────────────────────────────────────

    local ui_healthy=false
    local api_healthy=false

    if wait_for_healthy "http://localhost:$ui_port" "UI (port $ui_port)" 120; then
        ui_healthy=true
    fi

    if wait_for_healthy "http://localhost:$api_port" "API (port $api_port)" 120; then
        api_healthy=true
    fi

    # ── Step 5: Report ───────────────────────────────────────────────────

    echo ""
    echo "=== Environment Ready ==="
    echo "  PR:     #$pr_number ($branch)"
    echo "  UI:     http://localhost:$ui_port $([ "$ui_healthy" = true ] && echo "(healthy)" || echo "(NOT RESPONDING)")"
    echo "  API:    http://localhost:$api_port $([ "$api_healthy" = true ] && echo "(healthy)" || echo "(NOT RESPONDING)")"
    echo "  DB:     localhost:$db_port"
    echo ""

    # Write metadata for status/teardown
    cat > "${worktree_dir}/.recon-env" <<ENVEOF
PR_NUMBER=$pr_number
BRANCH=$branch
UI_PORT=$ui_port
API_PORT=$api_port
DB_PORT=$db_port
PROJECT_NAME=$project_name
COMPOSE_FILE=$compose_file
STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
UI_HEALTHY=$ui_healthy
API_HEALTHY=$api_healthy
ENVEOF

    if [ "$ui_healthy" = false ] || [ "$api_healthy" = false ]; then
        warn "Some services are not healthy. Recon may produce incomplete results."
        return 3  # Special exit code: running but not fully healthy
    fi

    return 0
}

# ─── Down ────────────────────────────────────────────────────────────────────

cmd_down() {
    local pr_number="${1:?Usage: recon-env.sh down <pr_number>}"
    local project_name="${PROJECT_PREFIX}-${pr_number}"
    local worktree_dir="${RECON_BASE}/${project_name}"

    echo ""
    log "Tearing down environment for PR #${pr_number}..."

    # ── Step 1: Stop Docker Compose ──────────────────────────────────────

    if [ -f "${worktree_dir}/.recon-env" ]; then
        source "${worktree_dir}/.recon-env"
        local compose_path="$worktree_dir/$COMPOSE_FILE"

        if [ -f "$compose_path" ]; then
            log "Stopping Docker Compose (project: $project_name)..."
            docker compose -p "$project_name" -f "$compose_path" down -v --remove-orphans 2>/dev/null || true
            ok "Docker Compose stopped"
        fi

        # Kill any processes on the allocated ports (fallback)
        for port in "$UI_PORT" "$API_PORT" "$DB_PORT"; do
            local pids
            pids=$(lsof -ti:"$port" 2>/dev/null || true)
            if [ -n "$pids" ]; then
                echo "$pids" | xargs kill 2>/dev/null || true
                log "Killed processes on port $port"
            fi
        done
    else
        # No metadata file — try to stop compose by project name anyway
        docker compose -p "$project_name" down -v --remove-orphans 2>/dev/null || true
    fi

    # ── Step 2: Remove worktree ──────────────────────────────────────────

    if [ -d "$worktree_dir" ]; then
        log "Removing worktree at $worktree_dir..."
        git worktree remove "$worktree_dir" --force 2>/dev/null || rm -rf "$worktree_dir"
        ok "Worktree removed"
    fi

    # ── Step 3: Prune ────────────────────────────────────────────────────

    git worktree prune 2>/dev/null || true

    ok "Environment for PR #${pr_number} fully cleaned up"
    echo ""
}

# ─── Status ──────────────────────────────────────────────────────────────────

cmd_status() {
    local pr_number="${1:?Usage: recon-env.sh status <pr_number>}"
    local project_name="${PROJECT_PREFIX}-${pr_number}"
    local worktree_dir="${RECON_BASE}/${project_name}"

    if [ ! -d "$worktree_dir" ]; then
        err "No environment found for PR #${pr_number}"
        return 1
    fi

    if [ ! -f "${worktree_dir}/.recon-env" ]; then
        warn "Environment directory exists but no metadata found"
        return 1
    fi

    source "${worktree_dir}/.recon-env"

    echo ""
    echo "=== PR #${pr_number} Environment Status ==="
    echo "  Branch:     $BRANCH"
    echo "  Started:    $STARTED_AT"
    echo "  Project:    $PROJECT_NAME"
    echo ""

    # Check if services are currently responding
    local ui_status api_status
    ui_status=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$UI_PORT" 2>/dev/null || echo "000")
    api_status=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$API_PORT" 2>/dev/null || echo "000")

    echo "  UI:   http://localhost:$UI_PORT → HTTP $ui_status $([ "$ui_status" != "000" ] && echo "(UP)" || echo "(DOWN)")"
    echo "  API:  http://localhost:$API_PORT → HTTP $api_status $([ "$api_status" != "000" ] && echo "(UP)" || echo "(DOWN)")"
    echo "  DB:   localhost:$DB_PORT"
    echo ""

    # Show Docker Compose status
    log "Container status:"
    docker compose -p "$PROJECT_NAME" ps 2>/dev/null || warn "Could not query Docker Compose"
    echo ""
}

# ─── List ────────────────────────────────────────────────────────────────────

cmd_list() {
    echo ""
    echo "=== Active Recon Environments ==="
    echo ""

    if [ ! -d "$RECON_BASE" ]; then
        echo "  (none)"
        echo ""
        return 0
    fi

    local found=false
    for env_dir in "$RECON_BASE"/${PROJECT_PREFIX}-*; do
        [ ! -d "$env_dir" ] && continue
        found=true

        local env_file="${env_dir}/.recon-env"
        if [ -f "$env_file" ]; then
            source "$env_file"
            local ui_status
            ui_status=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$UI_PORT" 2>/dev/null || echo "000")
            local status_icon
            [ "$ui_status" != "000" ] && status_icon="${GREEN}UP${NC}" || status_icon="${RED}DOWN${NC}"

            printf "  PR #%-4s  %-30s  UI=:%s  API=:%s  %b\n" \
                "$PR_NUMBER" "$BRANCH" "$UI_PORT" "$API_PORT" "$status_icon"
        else
            printf "  %-40s  (no metadata)\n" "$(basename "$env_dir")"
        fi
    done

    if [ "$found" = false ]; then
        echo "  (none)"
    fi

    echo ""
}

# ─── Nuke ────────────────────────────────────────────────────────────────────

cmd_nuke() {
    echo ""
    warn "Tearing down ALL recon environments..."
    echo ""

    if [ ! -d "$RECON_BASE" ]; then
        ok "No environments to clean up"
        return 0
    fi

    for env_dir in "$RECON_BASE"/${PROJECT_PREFIX}-*; do
        [ ! -d "$env_dir" ] && continue

        local dir_name
        dir_name=$(basename "$env_dir")
        local pr_num
        pr_num=$(echo "$dir_name" | sed "s/${PROJECT_PREFIX}-//")

        cmd_down "$pr_num" 2>/dev/null || true
    done

    # Final cleanup
    rm -rf "$RECON_BASE"
    git worktree prune 2>/dev/null || true

    ok "All recon environments destroyed"
    echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────

cmd="${1:-help}"
shift || true

case "$cmd" in
    up)     cmd_up "$@" ;;
    down)   cmd_down "$@" ;;
    status) cmd_status "$@" ;;
    list)   cmd_list ;;
    nuke)   cmd_nuke ;;
    ports)  allocate_ports "$@" ;;
    *)
        echo "Recon Environment Manager"
        echo ""
        echo "Usage:"
        echo "  recon-env.sh up     <pr_number> <branch> <ui_port> <api_port> <db_port> [compose_file]"
        echo "  recon-env.sh down   <pr_number>"
        echo "  recon-env.sh status <pr_number>"
        echo "  recon-env.sh list"
        echo "  recon-env.sh nuke"
        echo "  recon-env.sh ports  <count>"
        echo ""
        echo "Environment variables used by docker-compose.yml:"
        echo "  RECON_UI_PORT   — frontend port"
        echo "  RECON_API_PORT  — backend port"
        echo "  RECON_DB_PORT   — database port"
        echo ""
        echo "Exit codes:"
        echo "  0 — success"
        echo "  1 — error"
        echo "  2 — worktree ready, compose file needed (Claude should generate one)"
        echo "  3 — running but not fully healthy"
        ;;
esac
