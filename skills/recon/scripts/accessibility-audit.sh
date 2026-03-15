#!/usr/bin/env bash
# Recon — Accessibility Audit
# Runs available accessibility tools against a target URL.
# Usage: ./accessibility-audit.sh <url>

set -euo pipefail

URL="${1:?Usage: accessibility-audit.sh <url>}"

echo "=== RECON ACCESSIBILITY AUDIT ==="
echo "Target: $URL"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

TOOLS_RUN=0

# ─── 1. axe-core ────────────────────────────────────────────────────────────

echo "--- axe-core ---"
if command -v npx &>/dev/null && npx @axe-core/cli --help &>/dev/null 2>&1; then
    echo "Running axe-core..."
    npx @axe-core/cli "$URL" --stdout 2>/dev/null || echo "[WARN] axe-core exited with errors"
    TOOLS_RUN=$((TOOLS_RUN + 1))
else
    echo "[SKIP] @axe-core/cli not available. Install with: npm i -g @axe-core/cli"
fi

echo ""

# ─── 2. pa11y ────────────────────────────────────────────────────────────────

echo "--- pa11y ---"
if command -v npx &>/dev/null && npx pa11y --help &>/dev/null 2>&1; then
    echo "Running pa11y..."
    npx pa11y "$URL" --reporter json 2>/dev/null || echo "[WARN] pa11y exited with errors"
    TOOLS_RUN=$((TOOLS_RUN + 1))
else
    echo "[SKIP] pa11y not available. Install with: npm i -g pa11y"
fi

echo ""

# ─── 3. Lighthouse ──────────────────────────────────────────────────────────

echo "--- Lighthouse ---"
if command -v npx &>/dev/null && npx lighthouse --help &>/dev/null 2>&1; then
    echo "Running Lighthouse (accessibility + best-practices only)..."
    npx lighthouse "$URL" \
        --only-categories=accessibility,best-practices \
        --output=json \
        --chrome-flags="--headless --no-sandbox" \
        --quiet 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    cats = data.get('categories', {})
    for name, cat in cats.items():
        score = cat.get('score', 0)
        score_pct = int((score or 0) * 100)
        print(f'  {cat.get(\"title\", name)}: {score_pct}/100')
    audits = data.get('audits', {})
    failures = [(k, v) for k, v in audits.items() if v.get('score') == 0 and v.get('details', {}).get('items')]
    if failures:
        print(f'  Failed audits: {len(failures)}')
        for k, v in failures[:10]:
            print(f'    - {v.get(\"title\", k)}')
except Exception as e:
    print(f'  [WARN] Could not parse Lighthouse output: {e}')
" 2>/dev/null || echo "[WARN] Lighthouse exited with errors"
    TOOLS_RUN=$((TOOLS_RUN + 1))
else
    echo "[SKIP] Lighthouse not available. Install with: npm i -g lighthouse"
fi

echo ""

# ─── Summary ────────────────────────────────────────────────────────────────

if [ "$TOOLS_RUN" -eq 0 ]; then
    echo "[INFO] No programmatic accessibility tools available."
    echo "[INFO] Recon will fall back to Playwright-based accessibility checks:"
    echo "  - Missing alt text on images"
    echo "  - Missing form labels"
    echo "  - Color contrast (via computed styles)"
    echo "  - Keyboard navigation (tab order)"
    echo "  - ARIA attribute validation"
    echo ""
    echo "For better results, install at least one tool:"
    echo "  npm i -g @axe-core/cli pa11y lighthouse"
else
    echo "Programmatic tools run: $TOOLS_RUN"
fi

echo ""
echo "=== ACCESSIBILITY AUDIT COMPLETE ==="
