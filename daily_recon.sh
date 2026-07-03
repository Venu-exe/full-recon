#!/bin/bash

# ==========================================================
# Fast Daily Hunting Recon Script
# Usage: ./daily_recon.sh target.com
#
# Optimized for speed: 10-12 minutes per domain
# Focuses on high-probability bugs (XSS, SSRF, IDOR, etc)
# Skips: port scanning, screenshots, nuclei, cloud enum
# ==========================================================

set -uo pipefail

CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
DIM='\033[2m'
RESET='\033[0m'

echo -e "${GREEN}"
cat << "EOF"
   ___ ___ ___ ___  _  _
  | _ \ __/ __/ _ \| \| |
  |   / _| (_| (_) | .  |
  |_|_\___\___\___/|_|\_|
EOF
echo -e "${RESET}${DIM}   fast daily hunting recon${RESET}"
echo -e "${DIM}   operator: venu-exe${RESET}"
echo ""

usage() {
    cat << USAGE
Usage: $0 <domain>

Fast recon for daily bug bounty hunting (~10-12 min per domain)
Optimized for finding: XSS, SSRF, IDOR, stored XSS, open redirects

Example:
  $0 example.com

Output saved to: recon_<domain>/
USAGE
    exit 0
}

case "${1:-}" in
    -h|--help) usage ;;
    "") echo "Usage: $0 <domain>"; exit 1 ;;
esac

DOMAIN=$1
OUTDIR="recon_$DOMAIN"
mkdir -p "$OUTDIR"/{subdomains,http,urls,gf_results}
cd "$OUTDIR" || exit 1

log() { echo -e "\n${GREEN}[*]${RESET} $1"; }
warn() { echo -e "${YELLOW}[!]${RESET} $1"; }
success() { echo -e "${GREEN}[+]${RESET} $1"; }
have() { command -v "$1" &>/dev/null; }

echo -e "${CYAN}=========================================="
echo -e "${GREEN}[*]${RESET} Fast Recon: $DOMAIN"
echo -e "${CYAN}==========================================${RESET}"

# ----------------------------------------------------------
# 1. FAST SUBDOMAIN ENUM (parallel)
# ----------------------------------------------------------
log "Subdomain enumeration (parallel)"

(subfinder -d "$DOMAIN" -silent -o subdomains/subfinder.txt 2>/dev/null) &
PID1=$!

(amass enum -passive -d "$DOMAIN" > subdomains/amass.txt 2>/dev/null) &
PID2=$!

(curl -s "https://crt.sh/?q=%25.$DOMAIN&output=json" 2>/dev/null | jq -r '.[].name_value' 2>/dev/null | sed 's/\*\.//g' | sort -u > subdomains/crtsh.txt) &
PID3=$!

wait $PID1 $PID2 $PID3 2>/dev/null

cat subdomains/subfinder.txt subdomains/amass.txt subdomains/crtsh.txt 2>/dev/null | \
    grep -E "\.$DOMAIN$|^$DOMAIN$" | sort -u > subdomains/final.txt

SUBCOUNT=$(wc -l < subdomains/final.txt 2>/dev/null || echo 0)
log "Found $SUBCOUNT subdomains"

# ----------------------------------------------------------
# 2. LIVE HOST CHECK
# ----------------------------------------------------------
log "Checking live hosts (httpx)"

if have httpx; then
    cat subdomains/final.txt | httpx -silent -title -status-code -follow-redirects \
        -o http/live_hosts.txt 2>/dev/null
    cat http/live_hosts.txt | awk '{print $1}' > http/live_urls.txt
    LIVECOUNT=$(wc -l < http/live_urls.txt 2>/dev/null || echo 0)
    success "Found $LIVECOUNT live hosts"
else
    warn "httpx not installed"
    cp subdomains/final.txt http/live_urls.txt
fi

# ----------------------------------------------------------
# 3. CRAWL + HISTORICAL URLS (parallel)
# ----------------------------------------------------------
log "Crawling + historical URLs (parallel)"

(katana -list http/live_urls.txt -jc -silent -o urls/crawled.txt 2>/dev/null) &
PID1=$!

(cat http/live_urls.txt | gau --subs > urls/gau.txt 2>/dev/null) &
PID2=$!

wait $PID1 $PID2 2>/dev/null

cat urls/crawled.txt urls/gau.txt 2>/dev/null | sort -u > urls/all_urls.txt
URLCOUNT=$(wc -l < urls/all_urls.txt 2>/dev/null || echo 0)
log "Found $URLCOUNT unique URLs"

# ----------------------------------------------------------
# 4. GF PATTERN FILTERING (high-value only)
# ----------------------------------------------------------
log "Filtering for high-value vulnerabilities"

mkdir -p ~/.gf 2>/dev/null

# Auto-create custom patterns if missing
[ ! -f "$HOME/.gf/comment-inject.json" ] && cat > "$HOME/.gf/comment-inject.json" << 'EOF'
{"flags": "-iE", "pattern": "(comment|message|content|body|text|review|feedback|post|reply)="}
EOF

[ ! -f "$HOME/.gf/ssti-extended.json" ] && cat > "$HOME/.gf/ssti-extended.json" << 'EOF'
{"flags": "-iE", "pattern": "(template|preview|render|report|invoice|email_template)="}
EOF

if have gf; then
    # Focus on high-probability vulns only
    for pattern in xss ssrf comment-inject ssti-extended idor; do
        cat urls/all_urls.txt | gf "$pattern" 2>/dev/null > "gf_results/${pattern}.txt" || true
    done
    
    XSS=$(wc -l < gf_results/xss.txt 2>/dev/null || echo 0)
    SSRF=$(wc -l < gf_results/ssrf.txt 2>/dev/null || echo 0)
    COMMENT=$(wc -l < gf_results/comment-inject.txt 2>/dev/null || echo 0)
    IDOR=$(wc -l < gf_results/idor.txt 2>/dev/null || echo 0)
    
    success "XSS: $XSS | SSRF: $SSRF | Comment-inject: $COMMENT | IDOR: $IDOR"
else
    warn "gf not installed"
fi

# ----------------------------------------------------------
# SUMMARY
# ----------------------------------------------------------
echo ""
echo -e "${CYAN}=========================================="
echo -e "${GREEN}[+]${RESET} Recon complete for $DOMAIN"
echo "=========================================="
echo ""
echo "Quick test commands:"
echo "  XSS candidates:     cat gf_results/xss.txt | head -5"
echo "  SSRF candidates:    cat gf_results/ssrf.txt | head -5"
echo "  Comment-inject:     cat gf_results/comment-inject.txt | head -5"
echo "  IDOR candidates:    cat gf_results/idor.txt | head -5"
echo ""
echo "Next: Use dalfox on xss.txt, test manually for SSRF/IDOR"
echo -e "${CYAN}==========================================${RESET}"
