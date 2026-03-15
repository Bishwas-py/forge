#!/usr/bin/env bash
# Recon — API Contract Validation
# Validates API responses against an OpenAPI/Swagger spec if one exists.
# Usage: ./api-contract.sh <api_base_url> [spec_path]

set -euo pipefail

API_URL="${1:?Usage: api-contract.sh <api_base_url> [spec_path]}"
SPEC_PATH="${2:-}"
API_URL="${API_URL%/}"

echo "=== RECON API CONTRACT VALIDATION ==="
echo "API: $API_URL"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# ─── 1. Find OpenAPI Spec ───────────────────────────────────────────────────

echo "--- OpenAPI Spec Discovery ---"
if [ -z "$SPEC_PATH" ]; then
    SPEC_URLS=(
        "$API_URL/openapi.json"
        "$API_URL/docs/openapi.json"
        "$API_URL/api/openapi.json"
        "$API_URL/swagger.json"
        "$API_URL/api-docs"
        "$API_URL/v1/openapi.json"
    )

    for url in "${SPEC_URLS[@]}"; do
        STATUS=$(curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)
        if [ "$STATUS" = "200" ]; then
            BODY_HEAD=$(curl -s "$url" 2>/dev/null | head -c 500 || true)
            if echo "$BODY_HEAD" | grep -qi '"openapi"\|"swagger"\|"paths"'; then
                SPEC_PATH="$url"
                echo "[PASS] Found OpenAPI spec at: $url"
                break
            fi
        fi
    done

    if [ -z "$SPEC_PATH" ]; then
        for local_path in openapi.json openapi.yaml swagger.json swagger.yaml docs/openapi.json api/openapi.json; do
            if [ -f "$local_path" ]; then
                SPEC_PATH="$local_path"
                echo "[PASS] Found local spec: $local_path"
                break
            fi
        done
    fi

    if [ -z "$SPEC_PATH" ]; then
        echo "[INFO] No OpenAPI spec found. Skipping contract validation."
        echo "[INFO] Recon will use AI-based response shape analysis instead."
        echo ""
        echo "=== API CONTRACT VALIDATION COMPLETE (no spec) ==="
        exit 0
    fi
fi

echo ""

# ─── 2. Fetch and Parse Spec ────────────────────────────────────────────────

echo "--- Spec Analysis ---"
if echo "$SPEC_PATH" | grep -q "^http"; then
    SPEC_CONTENT=$(curl -s "$SPEC_PATH" 2>/dev/null || true)
else
    SPEC_CONTENT=$(cat "$SPEC_PATH" 2>/dev/null || true)
fi

if [ -z "$SPEC_CONTENT" ]; then
    echo "[WARN] Could not read spec from: $SPEC_PATH"
    echo "=== API CONTRACT VALIDATION COMPLETE ==="
    exit 0
fi

# Write spec to temp file for safe python parsing
SPEC_TMP=$(mktemp)
echo "$SPEC_CONTENT" > "$SPEC_TMP"

python3 -c "
import json, sys

try:
    with open('$SPEC_TMP') as f:
        spec = json.load(f)
except Exception as e:
    print(f'[WARN] Could not parse spec as JSON: {e}')
    sys.exit(0)

version = spec.get('openapi', spec.get('swagger', 'unknown'))
title = spec.get('info', {}).get('title', 'Unknown API')
print(f'Spec version: {version}')
print(f'API title: {title}')

paths = spec.get('paths', {})
print(f'Documented endpoints: {len(paths)}')
print('')

for path, methods in sorted(paths.items()):
    for method in sorted(methods.keys()):
        if method in ('get', 'post', 'put', 'patch', 'delete'):
            op = methods[method]
            summary = op.get('summary', op.get('operationId', ''))
            print(f'  {method.upper():7s} {path}  -- {summary}')
" 2>/dev/null || echo "[WARN] Could not parse OpenAPI spec"

echo ""

# ─── 3. Endpoint Liveness Check ─────────────────────────────────────────────

echo "--- Endpoint Liveness ---"
python3 -c "
import json, subprocess, sys

try:
    with open('$SPEC_TMP') as f:
        spec = json.load(f)
except:
    sys.exit(0)

paths = spec.get('paths', {})
base = '$API_URL'
checked = 0
failed = 0

for path, methods in sorted(paths.items()):
    if 'get' in methods:
        if '{' in path:
            continue
        url = f'{base}{path}'
        try:
            result = subprocess.run(
                ['curl', '-s', '-o', '/dev/null', '-w', '%{http_code}', url],
                capture_output=True, text=True, timeout=10
            )
            status = result.stdout.strip()
            checked += 1
            if status.startswith('2') or status.startswith('3'):
                print(f'  [PASS] GET {path} -> {status}')
            elif status == '401' or status == '403':
                print(f'  [INFO] GET {path} -> {status} (auth required)')
            elif status == '404':
                print(f'  [WARN] GET {path} -> 404 (documented but not found)')
                failed += 1
            else:
                print(f'  [WARN] GET {path} -> {status}')
                failed += 1
        except Exception as e:
            print(f'  [WARN] GET {path} -> error: {e}')
            failed += 1

print(f'')
print(f'Checked: {checked}, Failed: {failed}')
" 2>/dev/null || echo "[WARN] Endpoint liveness check failed"

rm -f "$SPEC_TMP"

echo ""
echo "=== API CONTRACT VALIDATION COMPLETE ==="
