#!/usr/bin/env bash
# Recon — Database Integrity Check
# Runs read-only integrity queries against a database.
# Usage: ./db-integrity.sh <engine> <connection_args>
#
# Supported engines:
#   postgres:  ./db-integrity.sh postgres "<container>" "<user>" "<dbname>"
#   mysql:     ./db-integrity.sh mysql "<container>" "<user>" "<dbname>"
#   sqlite:    ./db-integrity.sh sqlite "<path_to_db>"
#
# All queries are SELECT-only. No data is modified.

set -euo pipefail

ENGINE="${1:?Usage: db-integrity.sh <engine> <connection_args...>}"

echo "=== RECON DB INTEGRITY CHECK ==="
echo "Engine: $ENGINE"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

run_postgres() {
    local CONTAINER="${2:?postgres requires: <container> <user> <dbname>}"
    local USER="${3:?postgres requires: <container> <user> <dbname>}"
    local DB="${4:?postgres requires: <container> <user> <dbname>}"

    run_pg() {
        docker exec -i "$CONTAINER" psql -U "$USER" -d "$DB" -t -A -c "$1" 2>/dev/null
    }

    echo "--- Foreign Key Orphans ---"
    FK_QUERY="SELECT
        tc.table_name AS child_table,
        kcu.column_name AS child_column,
        ccu.table_name AS parent_table,
        ccu.column_name AS parent_column
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema = 'public';"

    FK_RESULTS=$(run_pg "$FK_QUERY" || true)
    if [ -z "$FK_RESULTS" ]; then
        echo "[INFO] No foreign key constraints found."
    else
        ORPHAN_COUNT=0
        while IFS='|' read -r child_table child_col parent_table parent_col; do
            [ -z "$child_table" ] && continue
            ORPHANS=$(run_pg "SELECT COUNT(*) FROM \"$child_table\" c LEFT JOIN \"$parent_table\" p ON c.\"$child_col\" = p.\"$parent_col\" WHERE p.\"$parent_col\" IS NULL AND c.\"$child_col\" IS NOT NULL;" || echo "0")
            ORPHANS=$(echo "$ORPHANS" | tr -d '[:space:]')
            if [ "$ORPHANS" != "0" ] && [ -n "$ORPHANS" ]; then
                echo "[CRITICAL] $child_table.$child_col -> $parent_table.$parent_col: $ORPHANS orphaned rows"
                ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
            fi
        done <<< "$FK_RESULTS"
        if [ "$ORPHAN_COUNT" -eq 0 ]; then
            echo "[PASS] No foreign key orphans detected."
        fi
    fi

    echo ""
    echo "--- Suspicious NULLs in Key Columns ---"
    TABLES=$(run_pg "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';" || true)
    while IFS= read -r table; do
        [ -z "$table" ] && continue
        for col in name title email; do
            HAS_COL=$(run_pg "SELECT column_name FROM information_schema.columns WHERE table_name = '$table' AND column_name = '$col' AND table_schema = 'public';" || true)
            if [ -n "$HAS_COL" ]; then
                NULL_COUNT=$(run_pg "SELECT COUNT(*) FROM \"$table\" WHERE \"$col\" IS NULL;" || echo "0")
                NULL_COUNT=$(echo "$NULL_COUNT" | tr -d '[:space:]')
                if [ "$NULL_COUNT" != "0" ] && [ -n "$NULL_COUNT" ]; then
                    echo "[WARN] $table.$col has $NULL_COUNT NULL values"
                fi
            fi
        done
    done <<< "$TABLES"

    echo ""
    echo "--- Duplicate Detection ---"
    while IFS= read -r table; do
        [ -z "$table" ] && continue
        for col in email username slug; do
            HAS_COL=$(run_pg "SELECT column_name FROM information_schema.columns WHERE table_name = '$table' AND column_name = '$col' AND table_schema = 'public';" || true)
            if [ -n "$HAS_COL" ]; then
                DUPES=$(run_pg "SELECT \"$col\", COUNT(*) as cnt FROM \"$table\" WHERE \"$col\" IS NOT NULL GROUP BY \"$col\" HAVING COUNT(*) > 1 LIMIT 5;" || true)
                if [ -n "$DUPES" ]; then
                    echo "[WARN] $table.$col has duplicates:"
                    echo "$DUPES" | while IFS='|' read -r val cnt; do
                        echo "  '$val' appears $cnt times"
                    done
                fi
            fi
        done
    done <<< "$TABLES"

    echo ""
    echo "--- Table Row Counts ---"
    while IFS= read -r table; do
        [ -z "$table" ] && continue
        COUNT=$(run_pg "SELECT COUNT(*) FROM \"$table\";" || echo "?")
        COUNT=$(echo "$COUNT" | tr -d '[:space:]')
        echo "  $table: $COUNT rows"
    done <<< "$TABLES"
}

run_mysql() {
    local CONTAINER="${2:?mysql requires: <container> <user> <dbname>}"
    local USER="${3:?mysql requires: <container> <user> <dbname>}"
    local DB="${4:?mysql requires: <container> <user> <dbname>}"

    run_my() {
        docker exec -i "$CONTAINER" mysql -u "$USER" -N -B -e "$1" "$DB" 2>/dev/null
    }

    echo "--- Foreign Key Orphans ---"
    FK_QUERY="SELECT TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
    FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
    WHERE REFERENCED_TABLE_NAME IS NOT NULL AND TABLE_SCHEMA = '$DB';"

    FK_RESULTS=$(run_my "$FK_QUERY" || true)
    if [ -z "$FK_RESULTS" ]; then
        echo "[INFO] No foreign key constraints found."
    else
        ORPHAN_COUNT=0
        while IFS=$'\t' read -r child_table child_col parent_table parent_col; do
            [ -z "$child_table" ] && continue
            ORPHANS=$(run_my "SELECT COUNT(*) FROM \`$child_table\` c LEFT JOIN \`$parent_table\` p ON c.\`$child_col\` = p.\`$parent_col\` WHERE p.\`$parent_col\` IS NULL AND c.\`$child_col\` IS NOT NULL;" || echo "0")
            if [ "$ORPHANS" != "0" ] && [ -n "$ORPHANS" ]; then
                echo "[CRITICAL] $child_table.$child_col -> $parent_table.$parent_col: $ORPHANS orphaned rows"
                ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
            fi
        done <<< "$FK_RESULTS"
        if [ "$ORPHAN_COUNT" -eq 0 ]; then
            echo "[PASS] No foreign key orphans detected."
        fi
    fi

    echo ""
    echo "--- Table Row Counts ---"
    TABLES=$(run_my "SHOW TABLES;" || true)
    while IFS= read -r table; do
        [ -z "$table" ] && continue
        COUNT=$(run_my "SELECT COUNT(*) FROM \`$table\`;" || echo "?")
        echo "  $table: $COUNT rows"
    done <<< "$TABLES"
}

run_sqlite() {
    local DB_PATH="${2:?sqlite requires: <path_to_db>}"

    echo "--- Table Row Counts ---"
    TABLES=$(sqlite3 "$DB_PATH" ".tables" 2>/dev/null | tr -s ' ' '\n' || true)
    while IFS= read -r table; do
        [ -z "$table" ] && continue
        COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM \"$table\";" 2>/dev/null || echo "?")
        echo "  $table: $COUNT rows"
    done <<< "$TABLES"

    echo ""
    echo "--- Foreign Key Violations ---"
    VIOLATIONS=$(sqlite3 "$DB_PATH" "PRAGMA foreign_key_check;" 2>/dev/null || true)
    if [ -z "$VIOLATIONS" ]; then
        echo "[PASS] No foreign key violations."
    else
        echo "[CRITICAL] Foreign key violations found:"
        echo "$VIOLATIONS"
    fi

    echo ""
    echo "--- Integrity Check ---"
    INTEGRITY=$(sqlite3 "$DB_PATH" "PRAGMA integrity_check;" 2>/dev/null || true)
    if [ "$INTEGRITY" = "ok" ]; then
        echo "[PASS] Database integrity OK."
    else
        echo "[CRITICAL] Database integrity issues:"
        echo "$INTEGRITY"
    fi
}

case "$ENGINE" in
    postgres) run_postgres "$@" ;;
    mysql) run_mysql "$@" ;;
    sqlite) run_sqlite "$@" ;;
    *) echo "[ERROR] Unsupported engine: $ENGINE. Supported: postgres, mysql, sqlite" ; exit 1 ;;
esac

echo ""
echo "=== DB INTEGRITY CHECK COMPLETE ==="
