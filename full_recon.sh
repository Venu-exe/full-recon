#!/bin/bash

# ==========================================================
# Comprehensive Bug Bounty Recon Automation Script
# Usage: ./full_recon.sh target.com
#
# Covers: subdomain enum (passive+active+permutation), ASN/IP
# discovery, live host probing, crawling, historical URLs,
# JS/secret hunting, API endpoint discovery, cloud bucket
# enum, port scanning, vuln-class filtering, screenshots.
#
# NOTE: This is a big toolchain. Not every tool will be
# installed on every machine -- the script skips gracefully
# if a tool is missing and tells you what to install.
# Only run against domains you are authorized to test.
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
echo -e "${RESET}${DIM}   full-spectrum recon automation${RESET}"
echo -e "${DIM}   operator: venu-exe${RESET}"
echo ""

usage() {
    cat << USAGE
Usage: $0 [options] <domain>

Options:
  -h, --help         Show this help message and exit

Arguments:
  <domain>            Target domain to run recon against (e.g. example.com)

Example:
  $0 example.com

What it does:
  Subdomain enum (passive+active+permutation) -> ASN/IP discovery ->
  live host probing -> port scanning -> crawling -> historical URLs ->
  JS/secret hunting -> API endpoint discovery -> cloud bucket enum ->
  gf pattern filtering -> screenshots -> nuclei CVE/misconfig scan

Output is saved to: recon_<domain>/
USAGE
    exit 0
}

case "${1:-}" in
    -h|--help)
        usage
        ;;
    "")
        echo "Usage: $0 <domain>"
        echo "Run '$0 --help' for more info."
        exit 1
        ;;
esac

DOMAIN=$1
OUTDIR="recon_$DOMAIN"
mkdir -p "$OUTDIR"/{subdomains,http,urls,js,api,cloud,ports,gf_results,screenshots,secrets}
cd "$OUTDIR" || exit 1

log() { echo -e "\n${GREEN}[*]${RESET} $1"; }
warn() { echo -e "${YELLOW}[!]${RESET} $1"; }
success() { echo -e "${GREEN}[+]${RESET} $1"; }
error() { echo -e "${RED}[-]${RESET} $1"; }
have() { command -v "$1" &>/dev/null; }

# ----------------------------------------------------------
# Tool check + interactive install prompt
# Usage: ensure_tool <binary_name> <install_command_string>
# If missing, asks the user y/n before installing.
# Returns 0 if the tool ends up available, 1 otherwise.
# ----------------------------------------------------------
ensure_tool() {
    local bin="$1"
    local install_cmd="$2"

    if have "$bin"; then
        return 0
    fi

    echo ""
    read -rp "$(echo -e ${YELLOW}[?]${RESET}) '$bin' is not installed. Install it now? [y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS])
            log "Running: $install_cmd"
            eval "$install_cmd"
            if have "$bin"; then
                success "'$bin' installed successfully."
                return 0
            else
                error "'$bin' install attempted but still not found on PATH."
                return 1
            fi
            ;;
        *)
            warn "Skipping '$bin' -- related step(s) will be skipped."
            return 1
            ;;
    esac
}

echo -e "${CYAN}=========================================="
echo " Full Recon: $DOMAIN"
echo " Output: $OUTDIR/"
echo "==========================================${RESET}"

# ----------------------------------------------------------
# 1. SUBDOMAIN ENUMERATION (passive + active + permutation)
# ----------------------------------------------------------
log "Passive subdomain enumeration (subfinder)"
if ensure_tool subfinder "go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"; then
    subfinder -d "$DOMAIN" -silent -o subdomains/subfinder.txt
fi

log "Passive subdomain enumeration (amass, passive mode)"
if ensure_tool amass "sudo pacman -S amass"; then
    amass enum -passive -d "$DOMAIN" -o subdomains/amass_passive.txt
fi

log "Certificate transparency (crt.sh)"
if have curl && have jq; then
    curl -s "https://crt.sh/?q=%25.$DOMAIN&output=json" \
        | jq -r '.[].name_value' 2>/dev/null \
        | sed 's/\*\.//g' | sort -u > subdomains/crtsh.txt
else
    warn "curl/jq not installed"
fi

# Combine all passive results
cat subdomains/subfinder.txt subdomains/amass_passive.txt subdomains/crtsh.txt 2>/dev/null \
    | grep -E "\.$DOMAIN$" | sort -u > subdomains/all_passive.txt

log "Active brute-force (puredns + wordlist)"
if ensure_tool puredns "go install github.com/d3mondev/puredns/v2@latest"; then
    if [ -f "$HOME/wordlists/subdomains.txt" ]; then
        puredns bruteforce "$HOME/wordlists/subdomains.txt" "$DOMAIN" -q > subdomains/bruteforce.txt
    else
        warn "wordlist missing (~/wordlists/subdomains.txt) -- get one from SecLists"
    fi
fi

log "Permutation scanning (gotator on known subdomains)"
if ensure_tool gotator "go install github.com/Josue87/gotator@latest"; then
    gotator -sub subdomains/all_passive.txt -perm /dev/null -depth 1 -numbers 3 -mindup -silent \
        > subdomains/permutations_raw.txt 2>/dev/null
    if have puredns; then
        puredns resolve subdomains/permutations_raw.txt -q > subdomains/permutations_resolved.txt
    fi
fi

cat subdomains/*.txt 2>/dev/null | grep -E "\.$DOMAIN$|^$DOMAIN$" | sort -u > subdomains/final_all.txt
log "Total unique subdomains found: $(wc -l < subdomains/final_all.txt)"

# ----------------------------------------------------------
# 2. ASN / IP RANGE DISCOVERY
# ----------------------------------------------------------
log "ASN / IP range discovery (amass intel)"
if have amass; then
    amass intel -org "$DOMAIN" -o subdomains/asn_org_lookup.txt 2>/dev/null
else
    warn "amass not installed -- skipping ASN lookup"
fi

# ----------------------------------------------------------
# 3. LIVE HOST DISCOVERY
# ----------------------------------------------------------
log "Probing live hosts (httpx)"
if ensure_tool httpx "go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest"; then
    cat subdomains/final_all.txt | httpx -silent -title -status-code -tech-detect -follow-redirects \
        -o http/live_hosts.txt
    cat http/live_hosts.txt | awk '{print $1}' > http/live_urls.txt
else
    warn "httpx not installed -- most later steps depend on this, install it first"
    touch http/live_urls.txt
fi

# ----------------------------------------------------------
# 4. PORT SCANNING
# ----------------------------------------------------------
log "Port scanning live hosts (naabu, top 1000 ports)"
if ensure_tool naabu "go install -v github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"; then
    cat http/live_urls.txt | sed 's~https\?://~~;s~/.*~~' | sort -u > ports/hosts_only.txt
    naabu -list ports/hosts_only.txt -top-ports 1000 -silent -o ports/open_ports.txt
fi

# ----------------------------------------------------------
# 5. CRAWLING + HISTORICAL URLS
# ----------------------------------------------------------
log "Crawling live hosts (katana)"
if ensure_tool katana "go install -v github.com/projectdiscovery/katana/cmd/katana@latest"; then
    katana -list http/live_urls.txt -jc -silent -o urls/crawled.txt
else
    touch urls/crawled.txt
fi

log "Historical URLs (gau)"
if ensure_tool gau "go install github.com/lc/gau/v2/cmd/gau@latest"; then
    cat http/live_urls.txt | gau --subs > urls/gau.txt 2>/dev/null
else
    touch urls/gau.txt
fi

log "Historical URLs (waybackurls, as second source)"
if ensure_tool waybackurls "go install github.com/tomnomnom/waybackurls@latest"; then
    cat http/live_urls.txt | waybackurls > urls/wayback.txt 2>/dev/null
else
    touch urls/wayback.txt
fi

cat urls/crawled.txt urls/gau.txt urls/wayback.txt 2>/dev/null | sort -u > urls/all_urls.txt
log "Total unique URLs found: $(wc -l < urls/all_urls.txt)"

# ----------------------------------------------------------
# 6. JS FILE DISCOVERY + SECRET/ENDPOINT EXTRACTION
# ----------------------------------------------------------
log "Extracting JS files"
grep -E "\.js($|\?)" urls/all_urls.txt | sort -u > js/js_files.txt

log "Mining JS files for endpoints/secrets (subjs + secretfinder-style grep)"
if ensure_tool subjs "go install github.com/lc/subjs@latest"; then
    cat http/live_urls.txt | subjs >> js/js_files.txt 2>/dev/null
    sort -u -o js/js_files.txt js/js_files.txt
fi
# lightweight inline grep for common secret patterns as a fallback
if have curl; then
    while read -r js_url; do
        curl -s "$js_url" 2>/dev/null
    done < <(head -n 50 js/js_files.txt) \
        | grep -Eo "(api[_-]?key|secret|token|aws_access_key_id|Bearer [A-Za-z0-9\-_]+)[\"': =]+[A-Za-z0-9\-_/+=]{10,}" \
        > secrets/js_secrets_sample.txt 2>/dev/null || true
fi

# ----------------------------------------------------------
# 7. API-SPECIFIC RECON
# ----------------------------------------------------------
log "Probing for API docs / specs (Swagger, OpenAPI, GraphQL)"
API_PATHS=("swagger.json" "swagger-ui.html" "api-docs" "api/swagger.json" "openapi.json" "graphql" "v1/swagger.json" "v2/api-docs")
if have httpx; then
    : > api/api_candidates.txt
    for host in $(cat http/live_urls.txt); do
        for path in "${API_PATHS[@]}"; do
            echo "$host/$path"
        done
    done > api/api_probe_list.txt
    cat api/api_probe_list.txt | httpx -silent -status-code -mc 200 -o api/found_api_endpoints.txt
else
    warn "httpx not installed -- skipping API probing"
fi

# ----------------------------------------------------------
# 8. CLOUD ASSET ENUMERATION (S3 / Azure / GCP buckets)
# ----------------------------------------------------------
log "Cloud bucket enumeration"
if ensure_tool cloud_enum "echo 'clone manually: git clone https://github.com/initstring/cloud_enum ~/tools/cloud_enum'"; then
    cloud_enum -k "$DOMAIN" -k "${DOMAIN%%.*}" -l cloud/cloud_enum_results.txt
fi

# ----------------------------------------------------------
# 9. VULN-CLASS CANDIDATE FILTERING (gf patterns)
# ----------------------------------------------------------
log "Filtering URLs by vulnerability class (gf patterns)"
if ensure_tool gf "go install github.com/tomnomnom/gf@latest"; then
    mkdir -p "$HOME/.gf"

    if [ ! -d "$HOME/.gf" ] || [ -z "$(ls -A "$HOME/.gf" 2>/dev/null)" ]; then
        echo "[!] No gf patterns found in ~/.gf -- get them with:"
        echo "    mkdir -p ~/.gf && git clone https://github.com/1ndianl33t/Gf-Patterns ~/Gf-Patterns && cp ~/Gf-Patterns/*.json ~/.gf/"
    fi

    # auto-generate custom patterns if missing (comment injection, extended ssti)
    if [ ! -f "$HOME/.gf/comment-inject.json" ]; then
        cat > "$HOME/.gf/comment-inject.json" << 'PATTERNEOF'
{
  "flags": "-iE",
  "pattern": "(comment|message|content|body|text|review|feedback|post|reply|description|bio)="
}
PATTERNEOF
    fi

    if [ ! -f "$HOME/.gf/ssti-extended.json" ]; then
        cat > "$HOME/.gf/ssti-extended.json" << 'PATTERNEOF'
{
  "flags": "-iE",
  "pattern": "(template|preview|render|report|invoice|email_template|doc_template|theme|layout)="
}
PATTERNEOF
    fi

    for pattern in xss ssrf redirect ssti sqli lfi idor rce interestingparams comment-inject ssti-extended; do
        cat urls/all_urls.txt | gf "$pattern" 2>/dev/null > "gf_results/${pattern}.txt" || true
    done
    log "gf results -- xss: $(wc -l < gf_results/xss.txt 2>/dev/null || echo 0) | ssrf: $(wc -l < gf_results/ssrf.txt 2>/dev/null || echo 0) | comment-inject: $(wc -l < gf_results/comment-inject.txt 2>/dev/null || echo 0) | ssti-extended: $(wc -l < gf_results/ssti-extended.txt 2>/dev/null || echo 0)"
fi

# ----------------------------------------------------------
# 10. SCREENSHOTS (visual recon)
# ----------------------------------------------------------
log "Screenshotting live hosts (gowitness)"
if ensure_tool gowitness "go install github.com/sensepost/gowitness@latest"; then
    gowitness file -f http/live_urls.txt -P screenshots/ --no-http-server &>/dev/null || true
fi

# ----------------------------------------------------------
# 11. QUICK NUCLEI SCAN (known CVEs / misconfigs -- optional)
# ----------------------------------------------------------
log "Running nuclei (known vulns + exposures templates)"
if ensure_tool nuclei "go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"; then
    nuclei -list http/live_urls.txt -tags cve,exposure,misconfig -silent -o ports/nuclei_findings.txt
fi

# ----------------------------------------------------------
# SUMMARY
# ----------------------------------------------------------
echo ""
echo -e "${CYAN}=========================================="
echo -e "${GREEN}[+]${RESET} Full recon complete for $DOMAIN"
echo -e "${GREEN}[+]${RESET} Results in: $OUTDIR/"
echo "--------------------------------------------------------"
echo " subdomains/final_all.txt        : all discovered subdomains"
echo " subdomains/asn_org_lookup.txt   : ASN/IP ranges owned by org"
echo " http/live_hosts.txt             : live hosts w/ status, title, tech"
echo " ports/open_ports.txt            : open ports per host"
echo " urls/all_urls.txt               : all crawled + historical URLs"
echo " js/js_files.txt                 : all discovered JS files"
echo " secrets/js_secrets_sample.txt   : possible leaked keys/tokens (sample)"
echo " api/found_api_endpoints.txt     : live Swagger/OpenAPI/GraphQL endpoints"
echo " cloud/cloud_enum_results.txt    : discovered cloud storage buckets"
echo " gf_results/*.txt                : URLs bucketed by vuln class"
echo " screenshots/                    : visual recon of all live hosts"
echo " ports/nuclei_findings.txt       : known CVE/misconfig hits"
echo -e "${CYAN}==========================================${RESET}"
echo ""
echo -e "${DIM}This still doesn't replace manual testing -- treat this output"
echo "as your prioritized target list, not a finished job.${RESET}"
