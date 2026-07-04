#!/bin/bash

# ==========================================================
# Triage Helper (ENHANCED) -- run AFTER daily_recon.sh / full_recon.sh
# Usage: ./triage_enhanced.sh <domain> [--format json|csv|markdown|text]
#
# Vuln classes covered:
#   1.  Open Redirect
#   2.  XSS / Text Reflection
#   3.  IDOR / BOLA
#   4.  SQL Injection
#   5.  SSRF
#   6.  Path Traversal / LFI
#   7.  SSTI (Server-Side Template Injection)
#   8.  RCE / Command Injection
#   9.  XXE (XML External Entity)
#   10. CORS / Origin-based
#   11. Mass Assignment / Parameter Pollution
#   12. File Upload
#   13. Authentication / Session
#   14. Insecure Deserialization
#   15. GraphQL / API Injection
#
# Features:
#   - Config file support (triage.conf)
#   - All previous bug fixes (path, stats-before-count, double-cd)
#   - Multiple export formats: text, json, csv, markdown
#   - Per-vuln severity ratings
#   - Statistics summary with all vuln classes
# ==========================================================

set -uo pipefail

# ============================================================
# Colors
# ============================================================
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

log()     { echo -e "\n${GREEN}[*]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $1"; }
error()   { echo -e "${RED}[x]${RESET} $1"; exit 1; }
section() { echo -e "\n${CYAN}== $1 ==${RESET}"; }

# ============================================================
# Defaults (all overridable in triage.conf)
# ============================================================
FORMAT="text"
DOMAIN=""
OUTDIR=""
CONFIG_FILE="triage.conf"

GF_RESULTS_DIR="gf_results"
URLS_FILE="urls/with_params.txt"

# --------------- Noise (skip these params) -----------------
NOISE_REGEX='^(af_|utm_|_c$|_ff$|_l$|_l10n$|_lrmc$|_plk$|_style$|_thumbnail_id$|_density$|cid$|ec$|ev$|ds$|v$|ver$|t$|tl$|hl$|pid$|pn$|pg$|mode$|format$|display$|campaign$|medium$|source$|srsltid$|ref$|fbclid$|gclid$|msclkid$)'

# --------------- 1. Open Redirect --------------------------
REDIRECT_PARAMS="url new_url redirect_uri returnurl refURL linkurl share_url startURL
canonicalUrl redirect return next dest continue target forward continue_url
callback_url goto previous return_to return_url target_url jump logout_url
login_redirect success_url failure_url after_login after_logout post_login_url
redirect_to redirectUrl redirectUri return_path back backUrl
exit_url homepage landingpage out redir RelayState"

# --------------- 2. XSS / Text Reflection ------------------
XSS_PARAMS="q search keyword name text title address city comment message feedback
review query subject content body description bio profile username tag tags category
filter sort order email phone location note memo caption label hint placeholder
display_name fullname first_name last_name company org role announcement
summary abstract excerpt intro intro_text welcome_message error_message
status_message alert msg notice banner headline teaser blurb"

# --------------- 3. IDOR / BOLA ----------------------------
IDOR_PARAMS="id ID user_id account_id order_id booking_id reservation_id invoice_id
product_id item_id listing_id post_id article_id document_id report_id
transaction_id payment_id shipment_id tracking_id hotel_id bookingId
activityId cityId site_id siteId tierId customer_id client_id member_id
employee_id staff_id org_id group_id team_id project_id ticket_id issue_id
task_id session_id request_id ref_id profile_id folder_id file_id asset_id
vendor_id seller_id buyer_id owner_id creator_id author_id driver_id
ride_id trip_id chat_id thread_id room_id appointment_id subscription_id
contract_id case_id claim_id policy_id lead_id deal_id opportunity_id
portfolio_id wallet_id card_id loan_id account_number invoice_number
order_number confirmation_number reference_number receipt_id"

# --------------- 4. SQL Injection --------------------------
SQLI_PARAMS="id user username email password search query filter sort order category
type status page limit offset start end from to date range min max price
amount level rank step index position count total num record entry row
product item cat subcat parent child node leaf branch root code slug"

# --------------- 5. SSRF -----------------------------------
SSRF_PARAMS="url uri endpoint host server host_url service backend proxy
webhook webhook_url callback callback_url feed feed_url rss atom
image image_url photo avatar logo icon banner thumb thumbnail
import import_url export_url download download_url fetch fetch_url
load load_url embed embed_url include include_url file file_url
src source resource resource_url target target_url dest destination
wsdl schema xsd xmlsrc remote_url api_url base_url site site_url
redirect_url request_url document_url page_url link next_url"

# --------------- 6. Path Traversal / LFI ------------------
LFI_PARAMS="file filename path filepath page template view layout theme module
lang language locale include load read action dir directory folder
root document doc content data src source log logfile config cfg ini
report template_file module_name plugin component extension skin style
asset media resource attachment download upload certificate cert"

# --------------- 7. SSTI -----------------------------------
SSTI_PARAMS="template template_file preview render report invoice email_template
doc_template theme layout skin name title greeting subject body content
message text description note welcome header footer signature banner
payload data input value query search filter username display_name
company org role status error msg notice"

# --------------- 8. RCE / Command Injection ----------------
RCE_PARAMS="cmd command exec execute run shell script code eval input query
ping host ip address domain target test debug shell_cmd bash_cmd
system os process job task action operation function call method
endpoint service api handler worker subprocess job_command cron
schedule task_name command_line arguments params options flags"

# --------------- 9. XXE ------------------------------------
XXE_PARAMS="xml data input body content payload document file upload import
feed rss atom export schema wsdl xsd transform xslt dtd entity
template report invoice receipt form config configuration settings
manifest metadata annotation description comment note"

# --------------- 10. CORS / Origin -------------------------
CORS_PARAMS="origin referrer referer callback jsonp jsonp_callback cb
callbackFn format output response_type return_type wrap wrapper
access_control domain whitelist allowed_origin trusted_origin"

# --------------- 11. Mass Assignment / HPP -----------------
MASSASSIGN_PARAMS="role admin is_admin superuser privilege level access scope
permission grant status active enabled disabled verified approved
rank tier plan subscription group team owner bypass override
hidden internal debug test mode feature flag config setting
price amount discount fee rate tax total override_price"

# --------------- 12. File Upload ---------------------------
UPLOAD_PARAMS="file upload filename file_name file_type content_type mime_type
ext extension attachment document image photo avatar logo
import data export backup restore archive zip tar gz
media asset resource blob binary chunk part"

# --------------- 13. Auth / Session ------------------------
AUTH_PARAMS="token access_token refresh_token auth_token api_key api_token
session session_id sid csrf csrf_token xsrf nonce state
code grant_type authorization bearer jwt secret key
password old_password new_password confirm_password
otp pin mfa two_factor totp magic_link invite_token
reset_token verify_token activation_token confirmation_token
ticket pass passphrase credential secret_key private_key"

# --------------- 14. Insecure Deserialization --------------
DESERIAL_PARAMS="data payload object blob serialized encoded base64 token
cache session state config settings preferences profile
import export backup restore input body content document
value param parameter argument option flag"

# --------------- 15. GraphQL / API Injection ---------------
GRAPHQL_PARAMS="query mutation subscription operationName variables
fields field filter where order_by limit offset page
search include exclude expand depth introspection
fragment spread alias directive operation type"

# ============================================================
# Statistics counters
# ============================================================
REDIRECT_COUNT=0
XSS_COUNT=0
IDOR_COUNT=0
SQLI_COUNT=0
SSRF_COUNT=0
LFI_COUNT=0
SSTI_COUNT=0
RCE_COUNT=0
XXE_COUNT=0
CORS_COUNT=0
MASSASSIGN_COUNT=0
UPLOAD_COUNT=0
AUTH_COUNT=0
DESERIAL_COUNT=0
GRAPHQL_COUNT=0
TOTAL_URLS=0

# ============================================================
# Helpers
# ============================================================
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log "Loading config from $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    fi
}

parse_args() {
    if [ -z "${1:-}" ]; then
        cat << USAGE
Usage: $0 <domain> [--format text|json|csv|markdown]

Examples:
  $0 agoda.com
  $0 agoda.com --format json
  $0 agoda.com --format markdown

Formats:
  text       Human readable (default)
  json       Machine-readable JSON
  csv        Spreadsheet / import
  markdown   GitHub/Notion friendly
USAGE
        exit 1
    fi

    DOMAIN=$1
    shift || true

    while [ $# -gt 0 ]; do
        case "$1" in
            --format)
                FORMAT="${2:-text}"
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

# Extract up to 2 unique example URLs for a given param name
extract_urls() {
    local param=$1
    local source_files=$2
    # shellcheck disable=SC2086
    grep -hoE "https?://[^\"' ]*[?&]${param}=[^&\"' ]*" \
        $source_files 2>/dev/null | sort -u | head -2
}

# ============================================================
# Shared loop engine
# run_vuln_loop <label> <severity> <counter_var>
#               "<gf files>" "<param list>" <callback_fn>
# ============================================================
run_vuln_loop() {
    local label="$1"
    local severity="$2"
    local counter_var="$3"
    local gf_files="$4"
    local param_list="$5"
    local callback="$6"

    for param in $param_list; do
        echo "$param" | grep -qE "$NOISE_REGEX" && continue
        local MATCH
        MATCH=$(extract_urls "$param" "$gf_files $URLS_FILE")
        if [ -n "$MATCH" ]; then
            local n
            n=$(echo "$MATCH" | wc -l)
            printf -v "$counter_var" '%d' "$(( ${!counter_var} + n ))"
            "$callback" "$label" "$severity" "$param" "$MATCH" "$n"
        fi
    done
}

# ============================================================
# TEXT output
# ============================================================
_OUT=""

_text_header() {
    local label="$1" hint="$2"
    {
        echo ""
        echo "###############################################"
        echo "# ${label}"
        echo "# ${hint}"
        echo "###############################################"
    } >> "$_OUT"
}

_text_hit() {
    local _label="$1" sev="$2" param="$3" match="$4" n="$5"
    echo -e "\n--- param: $param [$sev] ---" >> "$_OUT"
    echo "$match" >> "$_OUT"
    echo -e "${GREEN}[+]${RESET} $param: $n example(s)"
}

output_text() {
    local output_file="triage/priority_list.txt"
    _OUT="$output_file"
    : > "$_OUT"

    {
        echo "###############################################"
        echo "# TRIAGE REPORT FOR: $DOMAIN"
        echo "# Generated: $(date)"
        echo "###############################################"
    } >> "$_OUT"

    _text_header "1. OPEN REDIRECT [High]" \
        "Test: swap value -> https://evil.com — does it redirect off-domain?"
    run_vuln_loop "Open Redirect" "High" REDIRECT_COUNT \
        "$GF_RESULTS_DIR/redirect.txt" "$REDIRECT_PARAMS" _text_hit

    _text_header "2. XSS / TEXT REFLECTION [Medium-High]" \
        "Test: inject XSSCANARY123<>\"' — is it reflected raw in response?"
    run_vuln_loop "XSS" "Medium" XSS_COUNT \
        "$GF_RESULTS_DIR/xss.txt $GF_RESULTS_DIR/comment-inject.txt" \
        "$XSS_PARAMS" _text_hit

    _text_header "3. IDOR / BOLA [Critical]" \
        "Test: change ID +/-1 with your own session — do you get another user's data?"
    run_vuln_loop "IDOR" "Critical" IDOR_COUNT \
        "$GF_RESULTS_DIR/idor.txt $GF_RESULTS_DIR/idor-extended.txt" \
        "$IDOR_PARAMS" _text_hit

    _text_header "4. SQL INJECTION [Critical]" \
        "Test: append ' OR '1'='1 or ' AND SLEEP(5)-- to param value."
    run_vuln_loop "SQLi" "Critical" SQLI_COUNT \
        "$GF_RESULTS_DIR/sqli.txt" "$SQLI_PARAMS" _text_hit

    _text_header "5. SSRF [Critical]" \
        "Test: point param at http://169.254.169.254/ or Burp Collaborator URL."
    run_vuln_loop "SSRF" "Critical" SSRF_COUNT \
        "$GF_RESULTS_DIR/ssrf.txt" "$SSRF_PARAMS" _text_hit

    _text_header "6. PATH TRAVERSAL / LFI [High]" \
        "Test: try ../../etc/passwd or /etc/passwd as param value."
    run_vuln_loop "LFI" "High" LFI_COUNT \
        "$GF_RESULTS_DIR/lfi.txt" "$LFI_PARAMS" _text_hit

    _text_header "7. SSTI [Critical]" \
        "Test: inject {{7*7}} or \${7*7} — if you see 49 in response it's vulnerable."
    run_vuln_loop "SSTI" "Critical" SSTI_COUNT \
        "$GF_RESULTS_DIR/ssti.txt $GF_RESULTS_DIR/ssti-extended.txt" \
        "$SSTI_PARAMS" _text_hit

    _text_header "8. RCE / COMMAND INJECTION [Critical]" \
        "Test: inject ;id or \$(id) — look for uid= in response body."
    run_vuln_loop "RCE" "Critical" RCE_COUNT \
        "$GF_RESULTS_DIR/rce.txt" "$RCE_PARAMS" _text_hit

    _text_header "9. XXE (XML External Entity) [High]" \
        "Test: POST XML with <!DOCTYPE x [<!ENTITY xxe SYSTEM 'file:///etc/passwd'>]>."
    run_vuln_loop "XXE" "High" XXE_COUNT \
        "$GF_RESULTS_DIR/xxe.txt" "$XXE_PARAMS" _text_hit

    _text_header "10. CORS / ORIGIN [Medium]" \
        "Test: send Origin: https://evil.com — does ACAO echo it back with credentials?"
    run_vuln_loop "CORS" "Medium" CORS_COUNT \
        "$GF_RESULTS_DIR/cors.txt" "$CORS_PARAMS" _text_hit

    _text_header "11. MASS ASSIGNMENT / HPP [High]" \
        "Test: add role=admin / is_admin=1 to PUT/POST body or URL params."
    run_vuln_loop "MassAssign" "High" MASSASSIGN_COUNT \
        "$GF_RESULTS_DIR/interestingparams.txt" "$MASSASSIGN_PARAMS" _text_hit

    _text_header "12. FILE UPLOAD [High]" \
        "Test: upload .php/.jsp with Content-Type: image/jpeg — can you execute it?"
    run_vuln_loop "Upload" "High" UPLOAD_COUNT \
        "$GF_RESULTS_DIR/upload.txt" "$UPLOAD_PARAMS" _text_hit

    _text_header "13. AUTH / SESSION ISSUES [Critical]" \
        "Test: replay tokens, swap JWT sub, try null/empty token, check entropy."
    run_vuln_loop "Auth" "Critical" AUTH_COUNT \
        "$GF_RESULTS_DIR/auth.txt" "$AUTH_PARAMS" _text_hit

    _text_header "14. INSECURE DESERIALIZATION [Critical]" \
        "Test: send ysoserial payloads in base64-encoded body/cookie/header params."
    run_vuln_loop "Deserial" "Critical" DESERIAL_COUNT \
        "$GF_RESULTS_DIR/deserial.txt" "$DESERIAL_PARAMS" _text_hit

    _text_header "15. GRAPHQL / API INJECTION [High]" \
        "Test: send {__schema{types{name}}} to /graphql — also try batching & introspection."
    run_vuln_loop "GraphQL" "High" GRAPHQL_COUNT \
        "$GF_RESULTS_DIR/graphql.txt" "$GRAPHQL_PARAMS" _text_hit

    TOTAL_URLS=$((REDIRECT_COUNT+XSS_COUNT+IDOR_COUNT+SQLI_COUNT+SSRF_COUNT+LFI_COUNT+SSTI_COUNT+RCE_COUNT+XXE_COUNT+CORS_COUNT+MASSASSIGN_COUNT+UPLOAD_COUNT+AUTH_COUNT+DESERIAL_COUNT+GRAPHQL_COUNT))

    {
        echo ""
        echo "###############################################"
        echo "# STATISTICS"
        echo "###############################################"
        printf "%-28s %s\n" "Total URLs:"              "$TOTAL_URLS"
        printf "%-28s %s\n" "Open Redirect:"           "$REDIRECT_COUNT"
        printf "%-28s %s\n" "XSS/Text:"                "$XSS_COUNT"
        printf "%-28s %s\n" "IDOR/BOLA:"               "$IDOR_COUNT"
        printf "%-28s %s\n" "SQL Injection:"           "$SQLI_COUNT"
        printf "%-28s %s\n" "SSRF:"                    "$SSRF_COUNT"
        printf "%-28s %s\n" "Path Traversal/LFI:"      "$LFI_COUNT"
        printf "%-28s %s\n" "SSTI:"                    "$SSTI_COUNT"
        printf "%-28s %s\n" "RCE/CmdInjection:"        "$RCE_COUNT"
        printf "%-28s %s\n" "XXE:"                     "$XXE_COUNT"
        printf "%-28s %s\n" "CORS:"                    "$CORS_COUNT"
        printf "%-28s %s\n" "Mass Assignment/HPP:"     "$MASSASSIGN_COUNT"
        printf "%-28s %s\n" "File Upload:"             "$UPLOAD_COUNT"
        printf "%-28s %s\n" "Auth/Session:"            "$AUTH_COUNT"
        printf "%-28s %s\n" "Insecure Deserial:"       "$DESERIAL_COUNT"
        printf "%-28s %s\n" "GraphQL/API:"             "$GRAPHQL_COUNT"
        echo "Generated: $(date)"
    } >> "$_OUT"

    log "Output: $OUTDIR/$output_file"
}

# ============================================================
# JSON output
# ============================================================
_json_tmp=""
_json_first=true

_json_hit() {
    local _label="$1" sev="$2" param="$3" match="$4" _n="$5"
    [ "$_json_first" = false ] && echo "      ," >> "$_json_tmp"
    _json_first=false
    echo "      {" >> "$_json_tmp"
    echo "        \"param\": \"$param\"," >> "$_json_tmp"
    echo "        \"severity\": \"$sev\"," >> "$_json_tmp"
    echo "        \"urls\": [" >> "$_json_tmp"
    echo "$match" | while read -r url; do
        echo "          \"$url\"," >> "$_json_tmp"
    done
    sed -i '$ s/,$//' "$_json_tmp"
    echo "        ]" >> "$_json_tmp"
    echo "      }" >> "$_json_tmp"
}

_json_open_section() {
    _json_first=true
    echo "    \"$1\": [" >> "$_json_tmp"
}
_json_close_section()      { echo "    ]," >> "$_json_tmp"; }
_json_close_section_last() { echo "    ]"  >> "$_json_tmp"; }

output_json() {
    local output_file="triage/priority_list.json"
    _json_tmp=$(mktemp)

    echo "  \"candidates\": {" >> "$_json_tmp"

    _json_open_section "open_redirect"
    run_vuln_loop "Open Redirect" "High" REDIRECT_COUNT \
        "$GF_RESULTS_DIR/redirect.txt" "$REDIRECT_PARAMS" _json_hit
    _json_close_section

    _json_open_section "xss_text"
    run_vuln_loop "XSS" "Medium" XSS_COUNT \
        "$GF_RESULTS_DIR/xss.txt $GF_RESULTS_DIR/comment-inject.txt" \
        "$XSS_PARAMS" _json_hit
    _json_close_section

    _json_open_section "idor"
    run_vuln_loop "IDOR" "Critical" IDOR_COUNT \
        "$GF_RESULTS_DIR/idor.txt $GF_RESULTS_DIR/idor-extended.txt" \
        "$IDOR_PARAMS" _json_hit
    _json_close_section

    _json_open_section "sqli"
    run_vuln_loop "SQLi" "Critical" SQLI_COUNT \
        "$GF_RESULTS_DIR/sqli.txt" "$SQLI_PARAMS" _json_hit
    _json_close_section

    _json_open_section "ssrf"
    run_vuln_loop "SSRF" "Critical" SSRF_COUNT \
        "$GF_RESULTS_DIR/ssrf.txt" "$SSRF_PARAMS" _json_hit
    _json_close_section

    _json_open_section "lfi"
    run_vuln_loop "LFI" "High" LFI_COUNT \
        "$GF_RESULTS_DIR/lfi.txt" "$LFI_PARAMS" _json_hit
    _json_close_section

    _json_open_section "ssti"
    run_vuln_loop "SSTI" "Critical" SSTI_COUNT \
        "$GF_RESULTS_DIR/ssti.txt $GF_RESULTS_DIR/ssti-extended.txt" \
        "$SSTI_PARAMS" _json_hit
    _json_close_section

    _json_open_section "rce"
    run_vuln_loop "RCE" "Critical" RCE_COUNT \
        "$GF_RESULTS_DIR/rce.txt" "$RCE_PARAMS" _json_hit
    _json_close_section

    _json_open_section "xxe"
    run_vuln_loop "XXE" "High" XXE_COUNT \
        "$GF_RESULTS_DIR/xxe.txt" "$XXE_PARAMS" _json_hit
    _json_close_section

    _json_open_section "cors"
    run_vuln_loop "CORS" "Medium" CORS_COUNT \
        "$GF_RESULTS_DIR/cors.txt" "$CORS_PARAMS" _json_hit
    _json_close_section

    _json_open_section "mass_assignment"
    run_vuln_loop "MassAssign" "High" MASSASSIGN_COUNT \
        "$GF_RESULTS_DIR/interestingparams.txt" "$MASSASSIGN_PARAMS" _json_hit
    _json_close_section

    _json_open_section "file_upload"
    run_vuln_loop "Upload" "High" UPLOAD_COUNT \
        "$GF_RESULTS_DIR/upload.txt" "$UPLOAD_PARAMS" _json_hit
    _json_close_section

    _json_open_section "auth_session"
    run_vuln_loop "Auth" "Critical" AUTH_COUNT \
        "$GF_RESULTS_DIR/auth.txt" "$AUTH_PARAMS" _json_hit
    _json_close_section

    _json_open_section "deserialization"
    run_vuln_loop "Deserial" "Critical" DESERIAL_COUNT \
        "$GF_RESULTS_DIR/deserial.txt" "$DESERIAL_PARAMS" _json_hit
    _json_close_section

    _json_open_section "graphql"
    run_vuln_loop "GraphQL" "High" GRAPHQL_COUNT \
        "$GF_RESULTS_DIR/graphql.txt" "$GRAPHQL_PARAMS" _json_hit
    _json_close_section_last

    echo "  }" >> "$_json_tmp"

    TOTAL_URLS=$((REDIRECT_COUNT+XSS_COUNT+IDOR_COUNT+SQLI_COUNT+SSRF_COUNT+LFI_COUNT+SSTI_COUNT+RCE_COUNT+XXE_COUNT+CORS_COUNT+MASSASSIGN_COUNT+UPLOAD_COUNT+AUTH_COUNT+DESERIAL_COUNT+GRAPHQL_COUNT))

    {
        echo "{"
        echo "  \"domain\": \"$DOMAIN\","
        echo "  \"generated\": \"$(date -Iseconds)\","
        echo "  \"statistics\": {"
        echo "    \"total_urls\": $TOTAL_URLS,"
        echo "    \"open_redirect\": $REDIRECT_COUNT,"
        echo "    \"xss_text\": $XSS_COUNT,"
        echo "    \"idor\": $IDOR_COUNT,"
        echo "    \"sqli\": $SQLI_COUNT,"
        echo "    \"ssrf\": $SSRF_COUNT,"
        echo "    \"lfi\": $LFI_COUNT,"
        echo "    \"ssti\": $SSTI_COUNT,"
        echo "    \"rce\": $RCE_COUNT,"
        echo "    \"xxe\": $XXE_COUNT,"
        echo "    \"cors\": $CORS_COUNT,"
        echo "    \"mass_assignment\": $MASSASSIGN_COUNT,"
        echo "    \"file_upload\": $UPLOAD_COUNT,"
        echo "    \"auth_session\": $AUTH_COUNT,"
        echo "    \"deserialization\": $DESERIAL_COUNT,"
        echo "    \"graphql\": $GRAPHQL_COUNT"
        echo "  },"
    } > "$output_file"
    cat "$_json_tmp" >> "$output_file"
    echo "}" >> "$output_file"
    rm -f "$_json_tmp"

    log "Output: $OUTDIR/$output_file"
}

# ============================================================
# CSV output
# ============================================================
_csv_file=""

_csv_hit() {
    local label="$1" sev="$2" param="$3" match="$4" _n="$5"
    echo "$match" | while read -r url; do
        printf '%s,%s,%s,%s\n' "$label" "$param" "$url" "$sev" >> "$_csv_file"
    done
}

output_csv() {
    local output_file="triage/priority_list.csv"
    _csv_file="$output_file"
    echo "Type,Parameter,URL,Severity" > "$output_file"

    run_vuln_loop "Open Redirect"   "High"     REDIRECT_COUNT   "$GF_RESULTS_DIR/redirect.txt"                                 "$REDIRECT_PARAMS"   _csv_hit
    run_vuln_loop "XSS"             "Medium"   XSS_COUNT        "$GF_RESULTS_DIR/xss.txt $GF_RESULTS_DIR/comment-inject.txt"  "$XSS_PARAMS"        _csv_hit
    run_vuln_loop "IDOR"            "Critical" IDOR_COUNT       "$GF_RESULTS_DIR/idor.txt $GF_RESULTS_DIR/idor-extended.txt"  "$IDOR_PARAMS"       _csv_hit
    run_vuln_loop "SQLi"            "Critical" SQLI_COUNT       "$GF_RESULTS_DIR/sqli.txt"                                    "$SQLI_PARAMS"       _csv_hit
    run_vuln_loop "SSRF"            "Critical" SSRF_COUNT       "$GF_RESULTS_DIR/ssrf.txt"                                    "$SSRF_PARAMS"       _csv_hit
    run_vuln_loop "LFI"             "High"     LFI_COUNT        "$GF_RESULTS_DIR/lfi.txt"                                     "$LFI_PARAMS"        _csv_hit
    run_vuln_loop "SSTI"            "Critical" SSTI_COUNT       "$GF_RESULTS_DIR/ssti.txt $GF_RESULTS_DIR/ssti-extended.txt" "$SSTI_PARAMS"       _csv_hit
    run_vuln_loop "RCE"             "Critical" RCE_COUNT        "$GF_RESULTS_DIR/rce.txt"                                     "$RCE_PARAMS"        _csv_hit
    run_vuln_loop "XXE"             "High"     XXE_COUNT        "$GF_RESULTS_DIR/xxe.txt"                                     "$XXE_PARAMS"        _csv_hit
    run_vuln_loop "CORS"            "Medium"   CORS_COUNT       "$GF_RESULTS_DIR/cors.txt"                                    "$CORS_PARAMS"       _csv_hit
    run_vuln_loop "Mass Assignment" "High"     MASSASSIGN_COUNT "$GF_RESULTS_DIR/interestingparams.txt"                       "$MASSASSIGN_PARAMS" _csv_hit
    run_vuln_loop "File Upload"     "High"     UPLOAD_COUNT     "$GF_RESULTS_DIR/upload.txt"                                  "$UPLOAD_PARAMS"     _csv_hit
    run_vuln_loop "Auth/Session"    "Critical" AUTH_COUNT       "$GF_RESULTS_DIR/auth.txt"                                    "$AUTH_PARAMS"       _csv_hit
    run_vuln_loop "Deserialization" "Critical" DESERIAL_COUNT   "$GF_RESULTS_DIR/deserial.txt"                                "$DESERIAL_PARAMS"   _csv_hit
    run_vuln_loop "GraphQL"         "High"     GRAPHQL_COUNT    "$GF_RESULTS_DIR/graphql.txt"                                 "$GRAPHQL_PARAMS"    _csv_hit

    TOTAL_URLS=$((REDIRECT_COUNT+XSS_COUNT+IDOR_COUNT+SQLI_COUNT+SSRF_COUNT+LFI_COUNT+SSTI_COUNT+RCE_COUNT+XXE_COUNT+CORS_COUNT+MASSASSIGN_COUNT+UPLOAD_COUNT+AUTH_COUNT+DESERIAL_COUNT+GRAPHQL_COUNT))
    log "Output: $OUTDIR/$output_file"
}

# ============================================================
# Markdown output
# ============================================================
_md_file=""

_md_hit() {
    local _label="$1" sev="$2" param="$3" match="$4" n="$5"
    {
        echo "### \`$param\` [$sev]"
        echo ""
        echo '```'
        echo "$match"
        echo '```'
        echo ""
    } >> "$_md_file"
    echo -e "${GREEN}[+]${RESET} $param: $n example(s)"
}

output_markdown() {
    local output_file="triage/priority_list.md"
    local tmp_body
    tmp_body=$(mktemp)
    _md_file="$tmp_body"

    _md_section() {
        local num="$1" title="$2" hint="$3"
        {
            echo "## $num. $title"
            echo ""
            echo "> $hint"
            echo ""
        } >> "$tmp_body"
    }

    _md_section 1  "Open Redirect [High]" \
        "Swap value -> \`https://evil.com\`. Does the app redirect off-domain?"
    run_vuln_loop "Open Redirect" "High" REDIRECT_COUNT \
        "$GF_RESULTS_DIR/redirect.txt" "$REDIRECT_PARAMS" _md_hit

    _md_section 2  "XSS / Text Reflection [Medium-High]" \
        "Inject \`XSSCANARY123<>\"'\`. Is it reflected raw in the response?"
    run_vuln_loop "XSS" "Medium" XSS_COUNT \
        "$GF_RESULTS_DIR/xss.txt $GF_RESULTS_DIR/comment-inject.txt" \
        "$XSS_PARAMS" _md_hit

    _md_section 3  "IDOR / BOLA [Critical]" \
        "Change ID +/-1 with your session. Do you get another user's object?"
    run_vuln_loop "IDOR" "Critical" IDOR_COUNT \
        "$GF_RESULTS_DIR/idor.txt $GF_RESULTS_DIR/idor-extended.txt" \
        "$IDOR_PARAMS" _md_hit

    _md_section 4  "SQL Injection [Critical]" \
        "Append \`' OR '1'='1\` or \`' AND SLEEP(5)--\` to the param value."
    run_vuln_loop "SQLi" "Critical" SQLI_COUNT \
        "$GF_RESULTS_DIR/sqli.txt" "$SQLI_PARAMS" _md_hit

    _md_section 5  "SSRF [Critical]" \
        "Point param at \`http://169.254.169.254/\` or your Burp Collaborator URL."
    run_vuln_loop "SSRF" "Critical" SSRF_COUNT \
        "$GF_RESULTS_DIR/ssrf.txt" "$SSRF_PARAMS" _md_hit

    _md_section 6  "Path Traversal / LFI [High]" \
        "Try \`../../etc/passwd\` or absolute \`/etc/passwd\` as param value."
    run_vuln_loop "LFI" "High" LFI_COUNT \
        "$GF_RESULTS_DIR/lfi.txt" "$LFI_PARAMS" _md_hit

    _md_section 7  "SSTI [Critical]" \
        "Inject \`{{7*7}}\` or \`\${7*7}\`. Seeing 49 in the response confirms SSTI."
    run_vuln_loop "SSTI" "Critical" SSTI_COUNT \
        "$GF_RESULTS_DIR/ssti.txt $GF_RESULTS_DIR/ssti-extended.txt" \
        "$SSTI_PARAMS" _md_hit

    _md_section 8  "RCE / Command Injection [Critical]" \
        "Inject \`;id\` or \`\$(id)\`. Look for uid= in response body."
    run_vuln_loop "RCE" "Critical" RCE_COUNT \
        "$GF_RESULTS_DIR/rce.txt" "$RCE_PARAMS" _md_hit

    _md_section 9  "XXE [High]" \
        "POST XML with \`<!DOCTYPE x [<!ENTITY xxe SYSTEM 'file:///etc/passwd'>]>\` and ref \`&xxe;\`."
    run_vuln_loop "XXE" "High" XXE_COUNT \
        "$GF_RESULTS_DIR/xxe.txt" "$XXE_PARAMS" _md_hit

    _md_section 10 "CORS / Origin [Medium]" \
        "Send \`Origin: https://evil.com\` — does ACAO echo it back with credentials?"
    run_vuln_loop "CORS" "Medium" CORS_COUNT \
        "$GF_RESULTS_DIR/cors.txt" "$CORS_PARAMS" _md_hit

    _md_section 11 "Mass Assignment / HPP [High]" \
        "Add \`role=admin\` or \`is_admin=1\` to PUT/POST body or URL."
    run_vuln_loop "MassAssign" "High" MASSASSIGN_COUNT \
        "$GF_RESULTS_DIR/interestingparams.txt" "$MASSASSIGN_PARAMS" _md_hit

    _md_section 12 "File Upload [High]" \
        "Upload .php/.jsp with Content-Type: image/jpeg. Can you execute it?"
    run_vuln_loop "Upload" "High" UPLOAD_COUNT \
        "$GF_RESULTS_DIR/upload.txt" "$UPLOAD_PARAMS" _md_hit

    _md_section 13 "Auth / Session Issues [Critical]" \
        "Replay tokens, swap JWT sub, try null/empty token, check token entropy."
    run_vuln_loop "Auth" "Critical" AUTH_COUNT \
        "$GF_RESULTS_DIR/auth.txt" "$AUTH_PARAMS" _md_hit

    _md_section 14 "Insecure Deserialization [Critical]" \
        "Send ysoserial payloads in base64 body/cookie. Watch for gadget execution."
    run_vuln_loop "Deserial" "Critical" DESERIAL_COUNT \
        "$GF_RESULTS_DIR/deserial.txt" "$DESERIAL_PARAMS" _md_hit

    _md_section 15 "GraphQL / API Injection [High]" \
        "Try \`{__schema{types{name}}}\` at /graphql. Also test batching & alias attacks."
    run_vuln_loop "GraphQL" "High" GRAPHQL_COUNT \
        "$GF_RESULTS_DIR/graphql.txt" "$GRAPHQL_PARAMS" _md_hit

    TOTAL_URLS=$((REDIRECT_COUNT+XSS_COUNT+IDOR_COUNT+SQLI_COUNT+SSRF_COUNT+LFI_COUNT+SSTI_COUNT+RCE_COUNT+XXE_COUNT+CORS_COUNT+MASSASSIGN_COUNT+UPLOAD_COUNT+AUTH_COUNT+DESERIAL_COUNT+GRAPHQL_COUNT))

    {
        echo "# Triage Report: $DOMAIN"
        echo ""
        echo "**Generated:** $(date)"
        echo ""
        echo "## Statistics"
        echo ""
        echo "| Vuln Class | Count | Severity |"
        echo "|------------|-------|----------|"
        echo "| Open Redirect | $REDIRECT_COUNT | High |"
        echo "| XSS / Text Reflection | $XSS_COUNT | Medium |"
        echo "| IDOR / BOLA | $IDOR_COUNT | Critical |"
        echo "| SQL Injection | $SQLI_COUNT | Critical |"
        echo "| SSRF | $SSRF_COUNT | Critical |"
        echo "| Path Traversal / LFI | $LFI_COUNT | High |"
        echo "| SSTI | $SSTI_COUNT | Critical |"
        echo "| RCE / Command Injection | $RCE_COUNT | Critical |"
        echo "| XXE | $XXE_COUNT | High |"
        echo "| CORS | $CORS_COUNT | Medium |"
        echo "| Mass Assignment / HPP | $MASSASSIGN_COUNT | High |"
        echo "| File Upload | $UPLOAD_COUNT | High |"
        echo "| Auth / Session | $AUTH_COUNT | Critical |"
        echo "| Insecure Deserialization | $DESERIAL_COUNT | Critical |"
        echo "| GraphQL / API Injection | $GRAPHQL_COUNT | High |"
        echo "| **TOTAL** | **$TOTAL_URLS** | |"
        echo ""
    } > "$output_file"
    cat "$tmp_body" >> "$output_file"
    rm -f "$tmp_body"

    log "Output: $OUTDIR/$output_file"
}

# ============================================================
# MAIN
# ============================================================
main() {
    parse_args "$@"
    load_config

    OUTDIR="recon_$DOMAIN"

    if [ ! -d "$OUTDIR" ]; then
        error "Can't find $OUTDIR — run daily_recon.sh $DOMAIN or full_recon.sh $DOMAIN first."
    fi

    cd "$OUTDIR" || exit 1
    mkdir -p triage

    section "Triaging $DOMAIN (format: $FORMAT)"

    case "$FORMAT" in
        text)     output_text     ;;
        json)     output_json     ;;
        csv)      output_csv      ;;
        markdown) output_markdown ;;
    esac

    TOTAL_URLS=$((REDIRECT_COUNT+XSS_COUNT+IDOR_COUNT+SQLI_COUNT+SSRF_COUNT+LFI_COUNT+SSTI_COUNT+RCE_COUNT+XXE_COUNT+CORS_COUNT+MASSASSIGN_COUNT+UPLOAD_COUNT+AUTH_COUNT+DESERIAL_COUNT+GRAPHQL_COUNT))

    echo ""
    echo -e "${CYAN}=========================================="
    echo -e "${GREEN}[+]${RESET} Triage complete for $DOMAIN"
    echo -e "${CYAN}==========================================${RESET}"
    echo ""
    printf "%-28s %s\n" "Vuln Class"               "Count"
    printf "%-28s %s\n" "----------------------------" "-----"
    printf "%-28s %s\n" "Open Redirect"             "$REDIRECT_COUNT"
    printf "%-28s %s\n" "XSS / Text Reflection"     "$XSS_COUNT"
    printf "%-28s %s\n" "IDOR / BOLA"               "$IDOR_COUNT"
    printf "%-28s %s\n" "SQL Injection"             "$SQLI_COUNT"
    printf "%-28s %s\n" "SSRF"                      "$SSRF_COUNT"
    printf "%-28s %s\n" "Path Traversal / LFI"      "$LFI_COUNT"
    printf "%-28s %s\n" "SSTI"                      "$SSTI_COUNT"
    printf "%-28s %s\n" "RCE / Cmd Injection"       "$RCE_COUNT"
    printf "%-28s %s\n" "XXE"                       "$XXE_COUNT"
    printf "%-28s %s\n" "CORS"                      "$CORS_COUNT"
    printf "%-28s %s\n" "Mass Assignment / HPP"     "$MASSASSIGN_COUNT"
    printf "%-28s %s\n" "File Upload"               "$UPLOAD_COUNT"
    printf "%-28s %s\n" "Auth / Session"            "$AUTH_COUNT"
    printf "%-28s %s\n" "Insecure Deserialization"  "$DESERIAL_COUNT"
    printf "%-28s %s\n" "GraphQL / API Injection"   "$GRAPHQL_COUNT"
    printf "%-28s %s\n" "----------------------------" "-----"
    printf "%-28s %s\n" "TOTAL"                     "$TOTAL_URLS"
    echo ""
    echo "Test priority order (highest impact first):"
    echo "  1. RCE / Cmd Injection   — direct shell access"
    echo "  2. SSRF                  — internal network / cloud metadata"
    echo "  3. SSTI                  — often leads to RCE"
    echo "  4. SQLi                  — data dump / auth bypass"
    echo "  5. IDOR / BOLA           — broken access control"
    echo "  6. Auth / Session        — account takeover"
    echo "  7. Insecure Deserial     — gadget chain RCE"
    echo "  8. XXE                   — file read / SSRF pivot"
    echo "  9. File Upload           — webshell potential"
    echo " 10. Path Traversal / LFI  — file read / config leak"
    echo " 11. Mass Assignment       — privilege escalation"
    echo " 12. GraphQL               — data exposure / injection"
    echo " 13. Open Redirect         — phishing / OAuth hijack"
    echo " 14. CORS                  — credential theft"
    echo " 15. XSS                   — needs user interaction"
    echo ""
}

main "$@"
