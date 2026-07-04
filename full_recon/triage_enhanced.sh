#!/bin/bash

# ==========================================================
# Triage Helper (ENHANCED) -- run AFTER daily_recon.sh finishes
# Usage: ./triage_enhanced.sh <domain> [--format json|csv|markdown|text]
#
# Features:
# - Config file support (triage.conf)
# - Multiple export formats
# - Statistics summary
# - Better error handling
#
# Output: triage/priority_list.* (in chosen format)
# ==========================================================

set -uo pipefail

# Color codes
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

# Logging functions
log()     { echo -e "\n${GREEN}[*]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $1"; }
error()   { echo -e "${RED}[✗]${RESET} $1"; exit 1; }
section() { echo -e "\n${CYAN}== $1 ==${RESET}"; }

# Default values
FORMAT="text"
DOMAIN=""
OUTDIR=""
CONFIG_FILE="triage.conf"

# Statistics
TOTAL_URLS=0
REDIRECT_COUNT=0
XSS_COUNT=0
IDOR_COUNT=0

# Default parameters (can be overridden in triage.conf)
NOISE_REGEX='^(af_|utm_|_c$|_ff$|_l$|_l10n$|_lrmc$|_plk$|_style$|_thumbnail_id$|_density$|cid$|ec$|ev$|ds$|v$|ver$|t$|tl$|hl$|pid$|pn$|pg$|mode$|format$|display$|key$|token$|campaign$|medium$|source$|srsltid$)'

REDIRECT_PARAMS="url new_url redirect_uri returnurl refURL linkurl share_url startURL canonicalUrl redirect return next dest continue target"
TEXT_PARAMS="q search keyword name text title address city comment message feedback review"
IDOR_PARAMS="hotel_id bookingId activityId cityId site_id siteId tierId id ID user_id account_id order_id booking_id reservation_id invoice_id"

GF_RESULTS_DIR="gf_results"
URLS_FILE="urls/with_params.txt"

# ============================================================
# Function: Load config file
# ============================================================
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log "Loading config from $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    fi
}

# ============================================================
# Function: Parse arguments
# ============================================================
parse_args() {
    if [ -z "${1:-}" ]; then
        echo "Usage: $0 <domain> [--format json|csv|markdown|text]"
        echo ""
        echo "Examples:"
        echo "  $0 agoda.com"
        echo "  $0 agoda.com --format json"
        echo "  $0 agoda.com --format csv"
        echo ""
        echo "Output formats:"
        echo "  text       - Human readable (default)"
        echo "  json       - JSON format"
        echo "  csv        - CSV format"
        echo "  markdown   - Markdown format"
        exit 1
    fi

    DOMAIN=$1
    shift || true

    while [ $# -gt 0 ]; do
        case "$1" in
            --format)
                FORMAT="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    if ! [[ "$FORMAT" =~ ^(text|json|csv|markdown)$ ]]; then
        error "Invalid format: $FORMAT. Must be: text, json, csv, markdown"
    fi
}

# ============================================================
# Function: Extract URLs for a parameter
# ============================================================
extract_urls() {
    local param=$1
    local source_files=$2

    grep -hoE "https?://[^\"' ]*[?&]${param}=[^&\"' ]*" \
        $source_files 2>/dev/null | sort -u | head -2
}

# ============================================================
# Function: Output in TEXT format
# ============================================================
output_text() {
    local output_file="$OUTDIR/triage/priority_list.txt"
    : > "$output_file"

    {
        echo "###############################################"
        echo "# TRIAGE REPORT FOR: $DOMAIN"
        echo "# Generated: $(date)"
        echo "###############################################"
        echo ""
        echo "###############################################"
        echo "# 1. OPEN REDIRECT CANDIDATES"
        echo "# Test: swap the value for https://example.com"
        echo "# and see if it actually redirects off-domain."
        echo "###############################################"
    } >> "$output_file"

    for param in $REDIRECT_PARAMS; do
        echo "$param" | grep -qE "$NOISE_REGEX" && continue
        MATCH=$(extract_urls "$param" "$GF_RESULTS_DIR/redirect.txt $URLS_FILE")
        if [ -n "$MATCH" ]; then
            ((REDIRECT_COUNT += $(echo "$MATCH" | wc -l)))
            echo -e "\n--- param: $param ---" >> "$output_file"
            echo "$MATCH" >> "$output_file"
            echo -e "${GREEN}[+]${RESET} $param: $(echo "$MATCH" | wc -l) example(s)"
        fi
    done

    {
        echo ""
        echo "###############################################"
        echo "# 2. XSS / TEXT-REFLECTION CANDIDATES"
        echo "# Test: replace value with a canary like"
        echo "# XSSCANARY123<>\"'  then view-source and check"
        echo "# if it comes back raw, encoded, or stripped."
        echo "###############################################"
    } >> "$output_file"

    for param in $TEXT_PARAMS; do
        echo "$param" | grep -qE "$NOISE_REGEX" && continue
        MATCH=$(extract_urls "$param" "$GF_RESULTS_DIR/xss.txt $GF_RESULTS_DIR/comment-inject.txt $URLS_FILE")
        if [ -n "$MATCH" ]; then
            ((XSS_COUNT += $(echo "$MATCH" | wc -l)))
            echo -e "\n--- param: $param ---" >> "$output_file"
            echo "$MATCH" >> "$output_file"
            echo -e "${GREEN}[+]${RESET} $param: $(echo "$MATCH" | wc -l) example(s)"
        fi
    done

    {
        echo ""
        echo "###############################################"
        echo "# 3. IDOR CANDIDATES"
        echo "# Test: while logged in, change the ID value by"
        echo "# +/-1 or +/-10 and see if you get someone else's"
        echo "# data back using YOUR OWN session/token."
        echo "###############################################"
    } >> "$output_file"

    for param in $IDOR_PARAMS; do
        echo "$param" | grep -qE "$NOISE_REGEX" && continue
        MATCH=$(extract_urls "$param" "$GF_RESULTS_DIR/idor.txt $GF_RESULTS_DIR/idor-extended.txt $URLS_FILE")
        if [ -n "$MATCH" ]; then
            ((IDOR_COUNT += $(echo "$MATCH" | wc -l)))
            echo -e "\n--- param: $param ---" >> "$output_file"
            echo "$MATCH" >> "$output_file"
            echo -e "${GREEN}[+]${RESET} $param: $(echo "$MATCH" | wc -l) example(s)"
        fi
    done

    TOTAL_URLS=$((REDIRECT_COUNT + XSS_COUNT + IDOR_COUNT))

    echo "" >> "$output_file"
    echo "###############################################" >> "$output_file"
    echo "# STATISTICS" >> "$output_file"
    echo "###############################################" >> "$output_file"
    echo "Total URLs: $TOTAL_URLS" >> "$output_file"
    echo "Open Redirect: $REDIRECT_COUNT" >> "$output_file"
    echo "XSS/Text: $XSS_COUNT" >> "$output_file"
    echo "IDOR: $IDOR_COUNT" >> "$output_file"
    echo "Generated: $(date)" >> "$output_file"

    log "Output: $output_file"
}

# ============================================================
# Function: Output in JSON format
# ============================================================
output_json() {
    local output_file="$OUTDIR/triage/priority_list.json"
    
    {
        echo "{"
        echo "  \"domain\": \"$DOMAIN\","
        echo "  \"generated\": \"$(date -Iseconds)\","
        echo "  \"statistics\": {"
        echo "    \"total_urls\": $TOTAL_URLS,"
        echo "    \"open_redirect\": $REDIRECT_COUNT,"
        echo "    \"xss_text\": $XSS_COUNT,"
        echo "    \"idor\": $IDOR_COUNT"
        echo "  },"
        echo "  \"candidates\": {"
        echo "    \"open_redirect\": ["
    } > "$output_file"

    local first=true
    for param in $REDIRECT_PARAMS; do
        echo "$param" | grep -qE "$NOISE_REGEX" && continue
        MATCH=$(extract_urls "$param" "$GF_RESULTS_DIR/redirect.txt $URLS_FILE")
        if [ -n "$MATCH" ]; then
            [ "$first" = false ] && echo "," >> "$output_file"
            first=false
            ((REDIRECT_COUNT += $(echo "$MATCH" | wc -l)))
            echo "      {" >> "$output_file"
            echo "        \"param\": \"$param\"," >> "$output_file"
            echo "        \"urls\": [" >> "$output_file"
            echo "$MATCH" | while read -r url; do
                echo "          \"$url\"," >> "$output_file"
            done
            sed -i '$ s/,$//' "$output_file"
            echo "        ]" >> "$output_file"
            echo "      }" >> "$output_file"
        fi
    done

    {
        echo "    ],"
        echo "    \"xss_text\": ["
    } >> "$output_file"

    first=true
    for param in $TEXT_PARAMS; do
        echo "$param" | grep -qE "$NOISE_REGEX" && continue
        MATCH=$(extract_urls "$param" "$GF_RESULTS_DIR/xss.txt $GF_RESULTS_DIR/comment-inject.txt $URLS_FILE")
        if [ -n "$MATCH" ]; then
            [ "$first" = false ] && echo "," >> "$output_file"
            first=false
            ((XSS_COUNT += $(echo "$MATCH" | wc -l)))
            echo "      {" >> "$output_file"
            echo "        \"param\": \"$param\"," >> "$output_file"
            echo "        \"urls\": [" >> "$output_file"
            echo "$MATCH" | while read -r url; do
                echo "          \"$url\"," >> "$output_file"
            done
            sed -i '$ s/,$//' "$output_file"
            echo "        ]" >> "$output_file"
            echo "      }" >> "$output_file"
        fi
    done

    {
        echo "    ],"
        echo "    \"idor\": ["
    } >> "$output_file"

    first=true
    for param in $IDOR_PARAMS; do
        echo "$param" | grep -qE "$NOISE_REGEX" && continue
        MATCH=$(extract_urls "$param" "$GF_RESULTS_DIR/idor.txt $GF_RESULTS_DIR/idor-extended.txt $URLS_FILE")
        if [ -n "$MATCH" ]; then
            [ "$first" = false ] && echo "," >> "$output_file"
            first=false
            ((IDOR_COUNT += $(echo "$MATCH" | wc -l)))
            echo "      {" >> "$output_file"
            echo "        \"param\": \"$param\"," >> "$output_file"
            echo "        \"urls\": [" >> "$output_file"
            echo "$MATCH" | while read -r url; do
                echo "          \"$url\"," >> "$output_file"
            done
            sed -i '$ s/,$//' "$output_file"
            echo "        ]" >> "$output_file"
            echo "      }" >> "$output_file"
        fi
    done

    TOTAL_URLS=$((REDIRECT_COUNT + XSS_COUNT + IDOR_COUNT))

    {
        echo "    ]"
        echo "  }"
        echo "}"
    } >> "$output_file"

    log "Output: $output_file"
}

# ============================================================
# Function: Output in CSV format
# ============================================================
output_csv() {
    local output_file="$OUTDIR/triage/priority_list.csv"
    
    echo "Type,Parameter,URL,Severity" > "$output_file"

    for param in $REDIRECT_PARAMS; do
        echo "$param" | grep -qE "$NOISE_REGEX" && continue
        MATCH=$(extract_urls "$param" "$GF_RESULTS_DIR/redirect.txt $URLS_FILE")
        if [ -n "$MATCH" ]; then
            ((REDIRECT_COUNT += $(echo "$MATCH" | wc -l)))
            echo "$MATCH" | while read -r url; do
                echo "Open Redirect,$param,$url,High" >> "$output_file"
            done
        fi
    done

    for param in $TEXT_PARAMS; do
        echo "$param" | grep -qE "$NOISE_REGEX" && continue
        MATCH=$(extract_urls "$param" "$GF_RESULTS_DIR/xss.txt $GF_RESULTS_DIR/comment-inject.txt $URLS_FILE")
        if [ -n "$MATCH" ]; then
            ((XSS_COUNT += $(echo "$MATCH" | wc -l)))
            echo "$MATCH" | while read -r url; do
                echo "XSS/Text,$param,$url,Medium" >> "$output_file"
            done
        fi
    done

    for param in $IDOR_PARAMS; do
        echo "$param" | grep -qE "$NOISE_REGEX" && continue
        MATCH=$(extract_urls "$param" "$GF_RESULTS_DIR/idor.txt $GF_RESULTS_DIR/idor-extended.txt $URLS_FILE")
        if [ -n "$MATCH" ]; then
            ((IDOR_COUNT += $(echo "$MATCH" | wc -l)))
            echo "$MATCH" | while read -r url; do
                echo "IDOR,$param,$url,Critical" >> "$output_file"
            done
        fi
    done

    TOTAL_URLS=$((REDIRECT_COUNT + XSS_COUNT + IDOR_COUNT))

    log "Output: $output_file"
}

# ============================================================
# Function: Output in Markdown format
# ============================================================
output_markdown() {
    local output_file="$OUTDIR/triage/priority_list.md"
    
    {
        echo "# Triage Report: $DOMAIN"
        echo ""
        echo "**Generated:** $(date)"
        echo ""
        echo "## Statistics"
        echo ""
        echo "| Metric | Count |"
        echo "|--------|-------|"
        echo "| Total URLs | $TOTAL_URLS |"
        echo "| Open Redirect | $REDIRECT_COUNT |"
        echo "| XSS/Text | $XSS_COUNT |"
        echo "| IDOR | $IDOR_COUNT |"
        echo ""
        echo "## 1. Open Redirect Candidates"
        echo ""
        echo "Test: swap the value for `https://example.com` and see if it redirects off-domain."
        echo ""
    } > "$output_file"

    for param in $REDIRECT_PARAMS; do
        echo "$param" | grep -qE "$NOISE_REGEX" && continue
        MATCH=$(extract_urls "$param" "$GF_RESULTS_DIR/redirect.txt $URLS_FILE")
        if [ -n "$MATCH" ]; then
            ((REDIRECT_COUNT += $(echo "$MATCH" | wc -l)))
            echo "### Parameter: \`$param\`" >> "$output_file"
            echo "" >> "$output_file"
            echo "\`\`\`" >> "$output_file"
            echo "$MATCH" >> "$output_file"
            echo "\`\`\`" >> "$output_file"
            echo "" >> "$output_file"
        fi
    done

    {
        echo "## 2. XSS / Text-Reflection Candidates"
        echo ""
        echo "Test: replace value with canary like \`XSSCANARY123<>\"'\` then view-source."
        echo ""
    } >> "$output_file"

    for param in $TEXT_PARAMS; do
        echo "$param" | grep -qE "$NOISE_REGEX" && continue
        MATCH=$(extract_urls "$param" "$GF_RESULTS_DIR/xss.txt $GF_RESULTS_DIR/comment-inject.txt $URLS_FILE")
        if [ -n "$MATCH" ]; then
            ((XSS_COUNT += $(echo "$MATCH" | wc -l)))
            echo "### Parameter: \`$param\`" >> "$output_file"
            echo "" >> "$output_file"
            echo "\`\`\`" >> "$output_file"
            echo "$MATCH" >> "$output_file"
            echo "\`\`\`" >> "$output_file"
            echo "" >> "$output_file"
        fi
    done

    {
        echo "## 3. IDOR Candidates"
        echo ""
        echo "Test: change ID value by ±1 or ±10 and see if you get someone else's data."
        echo ""
    } >> "$output_file"

    for param in $IDOR_PARAMS; do
        echo "$param" | grep -qE "$NOISE_REGEX" && continue
        MATCH=$(extract_urls "$param" "$GF_RESULTS_DIR/idor.txt $GF_RESULTS_DIR/idor-extended.txt $URLS_FILE")
        if [ -n "$MATCH" ]; then
            ((IDOR_COUNT += $(echo "$MATCH" | wc -l)))
            echo "### Parameter: \`$param\`" >> "$output_file"
            echo "" >> "$output_file"
            echo "\`\`\`" >> "$output_file"
            echo "$MATCH" >> "$output_file"
            echo "\`\`\`" >> "$output_file"
            echo "" >> "$output_file"
        fi
    done

    TOTAL_URLS=$((REDIRECT_COUNT + XSS_COUNT + IDOR_COUNT))

    log "Output: $output_file"
}

# ============================================================
# MAIN
# ============================================================
main() {
    parse_args "$@"
    load_config

    OUTDIR="recon_$DOMAIN"

    if [ ! -d "$OUTDIR" ]; then
        error "Can't find $OUTDIR -- run daily_recon.sh $DOMAIN first."
    fi

    cd "$OUTDIR" || exit 1
    mkdir -p triage

    section "Triaging $DOMAIN (format: $FORMAT)"

    case "$FORMAT" in
        text)
            output_text
            ;;
        json)
            output_json
            ;;
        csv)
            output_csv
            ;;
        markdown)
            output_markdown
            ;;
    esac

    TOTAL_URLS=$((REDIRECT_COUNT + XSS_COUNT + IDOR_COUNT))

    echo ""
    echo -e "${CYAN}=========================================="
    echo -e "${GREEN}[+]${RESET} Triage complete!"
    echo -e "${CYAN}==========================================${RESET}"
    echo ""
    echo "Statistics:"
    echo "  Total URLs: $TOTAL_URLS"
    echo "  Open Redirect: $REDIRECT_COUNT"
    echo "  XSS/Text: $XSS_COUNT"
    echo "  IDOR: $IDOR_COUNT"
    echo ""
    echo "Test in priority order:"
    echo "  1. Open Redirect (quick yes/no)"
    echo "  2. XSS (needs canary + view-source)"
    echo "  3. IDOR (needs real session)"
    echo ""
}

main "$@"
