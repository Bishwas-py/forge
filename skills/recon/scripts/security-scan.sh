#!/usr/bin/env bash
# Recon — Security Scan
# Runs deterministic security checks against a target URL.
# Usage: ./security-scan.sh <base_url>

set -euo pipefail

BASE_URL="${1:?Usage: security-scan.sh <base_url>}"
BASE_URL="${BASE_URL%/}"

echo "=== RECON SECURITY SCAN ==="
echo "Target: $BASE_URL"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# ─── 1. HTTP Security Headers ───────────────────────────────────────────────

echo "--- HTTP Security Headers ---"
HEADERS=$(curl -sI -o /dev/null -w '%{http_code}' --dump-header /dev/stdout "$BASE_URL" 2>/dev/null || true)

check_header() {
    local header_name="$1"
    local severity="$2"
    local description="$3"
    if echo "$HEADERS" | grep -qi "^${header_name}:"; then
        local value
        value=$(echo "$HEADERS" | grep -i "^${header_name}:" | head -1 | sed 's/^[^:]*: *//' | tr -d '\r')
        echo "[PASS] $header_name: $value"
    else
        echo "[$severity] $header_name: MISSING — $description"
    fi
}

check_header "Strict-Transport-Security" "WARN" "No HSTS header. Browsers will allow HTTP connections."
check_header "X-Content-Type-Options" "WARN" "Missing nosniff. Browser may MIME-sniff responses."
check_header "X-Frame-Options" "WARN" "No clickjacking protection via X-Frame-Options."
check_header "Content-Security-Policy" "WARN" "No CSP header. XSS mitigation reduced."
check_header "X-XSS-Protection" "INFO" "Legacy XSS protection header not set."
check_header "Referrer-Policy" "INFO" "No referrer policy. Browser uses default (may leak URLs)."
check_header "Permissions-Policy" "INFO" "No permissions policy. Browser features unrestricted."

echo ""

# ─── 2. CORS Configuration ──────────────────────────────────────────────────

echo "--- CORS Configuration ---"
CORS_RESPONSE=$(curl -sI -H "Origin: https://evil-attacker.com" "$BASE_URL" 2>/dev/null || true)
ACAO=$(echo "$CORS_RESPONSE" | grep -i "^access-control-allow-origin:" | sed 's/^[^:]*: *//' | tr -d '\r' || true)
ACAC=$(echo "$CORS_RESPONSE" | grep -i "^access-control-allow-credentials:" | sed 's/^[^:]*: *//' | tr -d '\r' || true)

if [ -z "$ACAO" ]; then
    echo "[PASS] No CORS headers returned for foreign origin."
elif [ "$ACAO" = "*" ]; then
    if echo "$ACAC" | grep -qi "true"; then
        echo "[CRITICAL] CORS: wildcard origin with credentials allowed. Any site can make authenticated requests."
    else
        echo "[WARN] CORS: wildcard origin (*). Any site can read responses."
    fi
elif echo "$ACAO" | grep -qi "evil-attacker.com"; then
    echo "[CRITICAL] CORS: reflects arbitrary origin (https://evil-attacker.com). Origin validation is broken."
else
    echo "[PASS] CORS: origin not reflected for foreign origin. Value: $ACAO"
fi

echo ""

# ─── 3. Cookie Flags ────────────────────────────────────────────────────────

echo "--- Cookie Security Flags ---"
COOKIE_HEADERS=$(curl -sI "$BASE_URL" 2>/dev/null | grep -i "^set-cookie:" || true)

if [ -z "$COOKIE_HEADERS" ]; then
    echo "[INFO] No cookies set on initial page load."
else
    echo "$COOKIE_HEADERS" | while IFS= read -r cookie_line; do
        cookie_name=$(echo "$cookie_line" | sed 's/^[^:]*: *//' | cut -d'=' -f1 | tr -d '\r')

        if ! echo "$cookie_line" | grep -qi "HttpOnly"; then
            echo "[WARN] Cookie '$cookie_name': missing HttpOnly flag. Accessible via JavaScript."
        fi
        if ! echo "$cookie_line" | grep -qi "Secure"; then
            echo "[WARN] Cookie '$cookie_name': missing Secure flag. Sent over HTTP."
        fi
        if ! echo "$cookie_line" | grep -qi "SameSite"; then
            echo "[WARN] Cookie '$cookie_name': missing SameSite flag. CSRF risk."
        fi
        if echo "$cookie_line" | grep -qi "HttpOnly" && echo "$cookie_line" | grep -qi "Secure" && echo "$cookie_line" | grep -qi "SameSite"; then
            echo "[PASS] Cookie '$cookie_name': all security flags present."
        fi
    done
fi

echo ""

# ─── 4. SSL/TLS Check ───────────────────────────────────────────────────────

echo "--- SSL/TLS ---"
if echo "$BASE_URL" | grep -q "^https://"; then
    HOST=$(echo "$BASE_URL" | sed 's|https://||' | cut -d'/' -f1 | cut -d':' -f1)
    PORT=$(echo "$BASE_URL" | sed 's|https://||' | cut -d'/' -f1 | grep -o ':[0-9]*' | tr -d ':' || echo "443")
    [ -z "$PORT" ] && PORT=443

    SSL_INFO=$(echo | openssl s_client -connect "$HOST:$PORT" -servername "$HOST" 2>/dev/null || true)
    if echo "$SSL_INFO" | grep -q "Verify return code: 0"; then
        echo "[PASS] SSL certificate is valid."
    else
        VERIFY_CODE=$(echo "$SSL_INFO" | grep "Verify return code:" | head -1 || echo "unknown")
        echo "[CRITICAL] SSL certificate issue: $VERIFY_CODE"
    fi
elif echo "$BASE_URL" | grep -q "localhost\|127\.0\.0\.1"; then
    echo "[INFO] Local development — SSL check skipped."
else
    echo "[WARN] Target is not using HTTPS."
fi

echo ""

# ─── 5. Open Redirect Check ─────────────────────────────────────────────────

echo "--- Open Redirect ---"
REDIRECT_PAYLOADS=(
    "${BASE_URL}/redirect?url=https://evil.com"
    "${BASE_URL}/login?next=https://evil.com"
    "${BASE_URL}/login?redirect=https://evil.com"
    "${BASE_URL}/auth/callback?redirect_uri=https://evil.com"
    "${BASE_URL}//evil.com"
)

FOUND_REDIRECT=false
for payload in "${REDIRECT_PAYLOADS[@]}"; do
    REDIR_LOCATION=$(curl -sI --max-redirs 0 "$payload" 2>/dev/null | grep -i "^location:" | sed 's/^[^:]*: *//' | tr -d '\r' || true)

    if echo "$REDIR_LOCATION" | grep -qi "evil.com"; then
        echo "[CRITICAL] Open redirect: $payload → $REDIR_LOCATION"
        FOUND_REDIRECT=true
    fi
done
if [ "$FOUND_REDIRECT" = false ]; then
    echo "[PASS] No open redirects detected on common patterns."
fi

echo ""

# ─── 6. Server Information Disclosure ────────────────────────────────────────

echo "--- Information Disclosure ---"
SERVER_HEADER=$(echo "$HEADERS" | grep -i "^server:" | sed 's/^[^:]*: *//' | tr -d '\r' || true)
POWERED_BY=$(echo "$HEADERS" | grep -i "^x-powered-by:" | sed 's/^[^:]*: *//' | tr -d '\r' || true)

if [ -n "$SERVER_HEADER" ]; then
    echo "[INFO] Server header: $SERVER_HEADER (consider removing version info)"
else
    echo "[PASS] No Server header exposed."
fi

if [ -n "$POWERED_BY" ]; then
    echo "[WARN] X-Powered-By: $POWERED_BY — reveals technology stack. Remove this header."
else
    echo "[PASS] No X-Powered-By header exposed."
fi

echo ""
echo "=== SECURITY SCAN COMPLETE ==="
