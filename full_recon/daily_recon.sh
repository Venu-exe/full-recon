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
section() { echo -e "\n${CYAN}== $1 ==${RESET}"; }
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
# 1.5. SCOPE FILTERING
# Keep a file at ~/scopes/<domain>_scope.txt listing in-scope
# wildcard patterns (one per line, e.g. "agoda.com", ".agoda.com")
# pulled straight from the program's HackerOne scope tab.
# ----------------------------------------------------------
SCOPEFILE="$HOME/scopes/${DOMAIN}_scope.txt"
if [ -f "$SCOPEFILE" ]; then
    log "Filtering against known scope ($SCOPEFILE)"
    grep -Ff "$SCOPEFILE" subdomains/final.txt > subdomains/in_scope.txt 2>/dev/null || true
    mv subdomains/final.txt subdomains/final_unfiltered.txt
    mv subdomains/in_scope.txt subdomains/final.txt
    success "Filtered to in-scope only: $(wc -l < subdomains/final.txt) (was $SUBCOUNT)"
else
    warn "No scope file at $SCOPEFILE -- skipping filter, verify scope manually before testing anything"
fi

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
# 2.5. NOISE-DOMAIN EXCLUSION
# Skip CDN/analytics/tracking/third-party hosts -- they waste 
# crawl time and never have the app logic we're after.
# ----------------------------------------------------------
log "Filtering out CDN/analytics/third-party noise domains"

# Comprehensive noise domain list (Google, Facebook, tracking, CDN, auth, etc.)
NOISE_DOMAINS="(cdn|static|assets|img|pix|bento|tags|analytics|tracking|metrics|google|facebook|doubleclick|amazon|cloudfront|cloudflare|fastly|akamai|datadog|sentry|intercom|mixpanel|segment|amplitude|appsflyer|firebase|twitter|github|slack|stripe|paypal|auth0|okta|login\.microsoftonline|accounts\.google|googleapis|gstatic|fonts\.google|pagead|adservice|ads|googletagmanager)"

grep -vE "^https?://(${NOISE_DOMAINS})[0-9]*\." http/live_urls.txt > http/live_urls_filtered.txt 2>/dev/null || cp http/live_urls.txt http/live_urls_filtered.txt
NOISECOUNT=$(( $(wc -l < http/live_urls.txt 2>/dev/null || echo 0) - $(wc -l < http/live_urls_filtered.txt 2>/dev/null || echo 0) ))
success "Excluded $NOISECOUNT noise hosts, $(wc -l < http/live_urls_filtered.txt) remain for crawling"

# ----------------------------------------------------------
# 3. CRAWL + HISTORICAL URLS (parallel)
# ----------------------------------------------------------
log "Crawling + historical URLs (parallel)"

(timeout 300 katana -list http/live_urls_filtered.txt -jc -silent -depth 2 -c 20 -rl 150 -o urls/crawled.txt 2>/dev/null) &
PID1=$!

(timeout 300 bash -c 'cat http/live_urls_filtered.txt | gau --subs' > urls/gau.txt 2>/dev/null) &
PID2=$!

wait $PID1 $PID2 2>/dev/null

cat urls/crawled.txt urls/gau.txt 2>/dev/null | sort -u > urls/all_urls.txt
URLCOUNT=$(wc -l < urls/all_urls.txt 2>/dev/null || echo 0)
log "Found $URLCOUNT unique URLs"

# ----------------------------------------------------------
# 3.5. PARAMS-ONLY FILTER + PARAM-NAME DEDUP
# Raw URL counts on large sites can run into the hundreds of
# thousands (same template, different IDs/dates). Keep only
# URLs with query params, then list the distinct param NAMES
# so you're triaging ~20 things instead of ~700,000 lines.
# ----------------------------------------------------------
grep '?' urls/all_urls.txt | sort -u > urls/with_params.txt
PARAMCOUNT=$(wc -l < urls/with_params.txt 2>/dev/null || echo 0)
log "Found $PARAMCOUNT URLs with query params (out of $URLCOUNT total)"

grep -oE '[?&][a-zA-Z0-9_]+=' urls/with_params.txt 2>/dev/null \
    | sed 's/[?&]//;s/=//' | sort -u > urls/distinct_param_names.txt
success "Distinct parameter names: $(wc -l < urls/distinct_param_names.txt)  (see urls/distinct_param_names.txt)"

# ----------------------------------------------------------
# 4. GF PATTERN FILTERING (high-value only, params-only set)
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

[ ! -f "$HOME/.gf/redirect.json" ] && cat > "$HOME/.gf/redirect.json" << 'EOF'
{"flags": "-iE", "pattern": "(url|redirect|return|next|dest|continue|target)="}
EOF

[ ! -f "$HOME/.gf/idor-extended.json" ] && cat > "$HOME/.gf/idor-extended.json" << 'EOF'
{"flags": "-iE", "pattern": "(user_id|account_id|order_id|booking_id|reservation_id|invoice_id)="}
EOF

if have gf; then
    # Focus on high-probability vulns only -- run against params-only set
    for pattern in xss ssrf comment-inject ssti-extended idor idor-extended redirect; do
        cat urls/with_params.txt | gf "$pattern" 2>/dev/null > "gf_results/${pattern}.txt" || true
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
# 5. DIFF AGAINST PREVIOUS RUN
# Highlights what's NEW since yesterday -- new subdomains/URLs
# are fresher, less-tested surface and worth checking first.
# ----------------------------------------------------------
cd ..
PREVDIR="recon_${DOMAIN}_previous"
if [ -d "$PREVDIR" ]; then
    log "Diffing against previous run"
    comm -13 <(sort "$PREVDIR/subdomains/final.txt" 2>/dev/null) <(sort "$OUTDIR/subdomains/final.txt" 2>/dev/null) \
        > "$OUTDIR/subdomains/NEW_subdomains.txt" 2>/dev/null || true
    comm -13 <(sort "$PREVDIR/urls/with_params.txt" 2>/dev/null) <(sort "$OUTDIR/urls/with_params.txt" 2>/dev/null) \
        > "$OUTDIR/urls/NEW_urls.txt" 2>/dev/null || true
    NEWSUBS=$(wc -l < "$OUTDIR/subdomains/NEW_subdomains.txt" 2>/dev/null || echo 0)
    NEWURLS=$(wc -l < "$OUTDIR/urls/NEW_urls.txt" 2>/dev/null || echo 0)
    success "New subdomains since last run: $NEWSUBS"
    success "New URLs since last run: $NEWURLS"
else
    warn "No previous run found -- this is the baseline, diffing starts tomorrow"
fi

# ============================================================
# AUTO-TRIAGE FINDINGS
# ============================================================
section "Running Triage"

# Create triage output directory
mkdir -p "$OUTDIR/triage"

# Check if triage script exists in current directory or parent
TRIAGE_SCRIPT=""
if [ -f "./triage_enhanced.sh" ]; then
    TRIAGE_SCRIPT="./triage_enhanced.sh"
elif [ -f "../triage_enhanced.sh" ]; then
    TRIAGE_SCRIPT="../triage_enhanced.sh"
fi

if [ -n "$TRIAGE_SCRIPT" ]; then
    chmod +x "$TRIAGE_SCRIPT"
    
    # Run triage in both text and json formats
    log "Generating priority lists (text + json formats)..."
    cd "$OUTDIR"
    "$TRIAGE_SCRIPT" "$DOMAIN" --format text 2>/dev/null || warn "Text format failed"
    "$TRIAGE_SCRIPT" "$DOMAIN" --format json 2>/dev/null || warn "JSON format failed"
    cd - > /dev/null
    
    success "✓ Triage complete!"
    log ""
    log "Output files generated:"
    if [ -f "$OUTDIR/triage/priority_list.txt" ]; then
        log "  ✓ recon_${DOMAIN}/triage/priority_list.txt"
    fi
    if [ -f "$OUTDIR/triage/priority_list.json" ]; then
        log "  ✓ recon_${DOMAIN}/triage/priority_list.json"
    fi
    log ""
    log "View results:"
    log "  cat recon_${DOMAIN}/triage/priority_list.txt"
    log "  cat recon_${DOMAIN}/triage/priority_list.json | jq ."
    log ""
else
    warn "triage_enhanced.sh not found in ./ or ../"
    log "To enable auto-triage, place triage_enhanced.sh in:"
    log "  - Same directory as daily_recon.sh, OR"
    log "  - Parent directory"
fi

log "Recon complete for $DOMAIN"
log "Output directory: $OUTDIR"

# Save this run as tomorrow's "previous" baseline
rm -rf "$PREVDIR"
cp -r "$OUTDIR" "$PREVDIR"
cd "$OUTDIR" || exit 1

# ----------------------------------------------------------
# GITHUB PUSH (optional)
# ----------------------------------------------------------
section "GitHub Integration"

GIT_REPO="$HOME/bug-bounty-recon"  # Change to your repo path
GIT_BRANCH="$(git config --get-regexp '^remote\.' 2>/dev/null | head -1 | awk '{print $2}' | sed 's/^//')" 
GIT_BRANCH="${GIT_BRANCH:-main}"

if [ -d "$GIT_REPO" ]; then
    log "Pushing results to GitHub ($GIT_REPO)"
    
    # Copy only the most important findings to avoid bloat
    GIT_OUTDIR="$GIT_REPO/findings/$DOMAIN"
    mkdir -p "$GIT_OUTDIR"
    
    # Copy key findings (not all URLs to avoid huge commits)
    cp subdomains/final.txt "$GIT_OUTDIR/subdomains.txt" 2>/dev/null || true
    cp http/live_urls.txt "$GIT_OUTDIR/live_hosts.txt" 2>/dev/null || true
    
    # Copy gf results
    mkdir -p "$GIT_OUTDIR/gf_results"
    cp gf_results/*.txt "$GIT_OUTDIR/gf_results/" 2>/dev/null || true
    
    # Copy triage if exists
    if [ -d "triage" ]; then
        cp -r triage "$GIT_OUTDIR/" 2>/dev/null || true
    fi
    
    # Create a summary file
    cat > "$GIT_OUTDIR/SUMMARY.txt" << SUMMARY
Domain: $DOMAIN
Date: $(date '+%Y-%m-%d %H:%M:%S')
Subdomains found: $(wc -l < subdomains/final.txt 2>/dev/null || echo 0)
Live hosts: $(wc -l < http/live_urls.txt 2>/dev/null || echo 0)
URLs with params: $(wc -l < urls/with_params.txt 2>/dev/null || echo 0)

High-value findings:
- XSS candidates: $(wc -l < gf_results/xss.txt 2>/dev/null || echo 0)
- SSRF candidates: $(wc -l < gf_results/ssrf.txt 2>/dev/null || echo 0)
- IDOR candidates: $(wc -l < gf_results/idor.txt 2>/dev/null || echo 0)
- Redirect candidates: $(wc -l < gf_results/redirect.txt 2>/dev/null || echo 0)
SUMMARY
    
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
echo "  NEW subdomains today:  cat subdomains/NEW_subdomains.txt"
echo "  NEW URLs today:        cat urls/NEW_urls.txt"
echo "  Distinct param names:  cat urls/distinct_param_names.txt"
echo "  XSS candidates:        cat gf_results/xss.txt | head -5"
echo "  SSRF candidates:       cat gf_results/ssrf.txt | head -5"
echo "  Redirect candidates:   cat gf_results/redirect.txt | head -5"
echo "  Comment-inject:        cat gf_results/comment-inject.txt | head -5"
echo "  IDOR candidates:       cat gf_results/idor.txt | head -5"
echo "  IDOR (extended):       cat gf_results/idor-extended.txt | head -5"
echo ""
echo "Next: Use dalfox on xss.txt, test manually for SSRF/IDOR/redirects"
echo -e "${CYAN}==========================================${RESET}"
