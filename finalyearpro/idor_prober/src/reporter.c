#include "reporter.h"
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define C_RESET   "\033[0m"
#define C_RED     "\033[1;31m"
#define C_GREEN   "\033[1;32m"
#define C_YELLOW  "\033[1;33m"
#define C_CYAN    "\033[1;36m"
#define C_BOLD    "\033[1m"
#define C_DIM     "\033[2m"

static const char *verdict_to_str(verdict_t v) {
    switch(v) {
        case VERDICT_DENIED: return "DENIED";
        case VERDICT_IDOR_CONFIRMED: return "IDOR_CONFIRMED";
        case VERDICT_SAFE_REMAPPED: return "SAFE_REMAPPED";
        case VERDICT_AMBIGUOUS: return "AMBIGUOUS";
        case VERDICT_NOT_JSON: return "NOT_JSON";
        default: return "UNKNOWN";
    }
}

static const char *verdict_color(verdict_t v, int use_color) {
    if (!use_color) return "";
    switch(v) {
        case VERDICT_DENIED: return C_GREEN;
        case VERDICT_IDOR_CONFIRMED: return C_RED;
        case VERDICT_SAFE_REMAPPED: return C_GREEN;
        case VERDICT_AMBIGUOUS: return C_YELLOW;
        case VERDICT_NOT_JSON: return C_YELLOW;
        default: return "";
    }
}

void summary_init(scan_summary_t *s) {
    if (!s) return;
    memset(s, 0, sizeof(*s));
}

void summary_add(scan_summary_t *s, const scan_result_t *r) {
    if (!s || !r) return;
    if (s->count >= s->cap) {
        int new_cap = s->cap == 0 ? 32 : s->cap * 2;
        scan_result_t *new_arr = realloc(s->results, new_cap * sizeof(scan_result_t));
        if (!new_arr) return;
        s->results = new_arr;
        s->cap = new_cap;
    }
    s->results[s->count] = *r;
    s->count++;
    
    switch (r->diff.verdict) {
        case VERDICT_DENIED: s->total_denied++; break;
        case VERDICT_IDOR_CONFIRMED: s->total_idor++; break;
        case VERDICT_SAFE_REMAPPED: s->total_safe++; break;
        case VERDICT_AMBIGUOUS: s->total_ambiguous++; break;
        case VERDICT_NOT_JSON: s->total_not_json++; break;
    }
}

void summary_free(scan_summary_t *s) {
    if (s && s->results) {
        free(s->results);
        s->results = NULL;
        s->cap = 0;
        s->count = 0;
    }
}

void report_print_result(FILE *out, const scan_result_t *r, int verbose, int use_color) {
    const char *reset = use_color ? C_RESET : "";
    const char *bold = use_color ? C_BOLD : "";
    const char *vcolor = verdict_color(r->diff.verdict, use_color);
    
    fprintf(out, "================================================================\n");
    fprintf(out, "TARGET: %s%s%s  [%s]\n", bold, r->url, reset, r->method);
    fprintf(out, "  A  -> HTTP %ld (%.2fs, %zu bytes)\n", r->status_a, r->time_a, r->body_len_a);
    fprintf(out, "  B  -> HTTP %ld (%.2fs, %zu bytes)\n", r->status_b_cross, r->time_b_cross, r->body_len_b_cross);
    if (r->have_baseline) {
        fprintf(out, "  B baseline -> HTTP %ld (%.2fs, %zu bytes)\n", r->status_b_own, r->time_b_own, r->body_len_b_own);
    }
    fprintf(out, "\n");
    fprintf(out, "  VERDICT: %s%s%s   (confidence: %d%%)\n", vcolor, verdict_to_str(r->diff.verdict), reset, r->diff.confidence);
    fprintf(out, "  cross_similarity=%.2f  shape=%.2f  value=%.2f", r->diff.cross_similarity, r->diff.shape_similarity, r->diff.value_similarity);
    if (r->have_baseline) {
        fprintf(out, "  baseline_similarity=%.2f\n", r->diff.baseline_similarity);
    } else {
        fprintf(out, "  baseline_similarity=n/a\n");
    }
    fprintf(out, "  reason: %s\n", r->diff.reason);
    
    if (r->hdr.missing_count > 0 || r->hdr.cache_concern) {
        fprintf(out, "\n  [Header Analysis]\n");
        if (r->hdr.missing_count > 0) {
            fprintf(out, "  Missing security headers: ");
            for (int i = 0; i < r->hdr.missing_count; i++) {
                fprintf(out, "%s%s", r->hdr.missing_headers[i], i == r->hdr.missing_count - 1 ? "" : ", ");
            }
            fprintf(out, "\n");
        }
        if (r->hdr.cache_concern) {
            fprintf(out, "  Cache concern: %s\n", r->hdr.cache_note);
        }
    }
    
    if (verbose) {
        fprintf(out, "\n");
        fprintf(out, "  [A body]        %.500s\n", r->body_a_preview);
        fprintf(out, "  [B cross body]  %.500s\n", r->body_b_cross_preview);
        if (r->have_baseline) {
            fprintf(out, "  [B own body]    %.500s\n", r->body_b_own_preview);
        }
    }
}

void report_progress(int current, int total, int use_color) {
    int width = 40;
    float pct = total > 0 ? (float)current / total : 0;
    int filled = (int)(pct * width);
    
    fprintf(stderr, "\r[%d/%d] %d%% ", current, total, (int)(pct * 100));
    if (use_color) fprintf(stderr, "%s", C_CYAN);
    fprintf(stderr, "[");
    for (int i = 0; i < width; i++) {
        if (i < filled) fprintf(stderr, "#");
        else fprintf(stderr, "-");
    }
    fprintf(stderr, "]");
    if (use_color) fprintf(stderr, "%s", C_RESET);
    fflush(stderr);
}

void report_print_summary(FILE *out, const scan_summary_t *s, int use_color) {
    const char *reset = use_color ? C_RESET : "";
    const char *red = use_color ? C_RED : "";
    const char *green = use_color ? C_GREEN : "";
    const char *yellow = use_color ? C_YELLOW : "";
    
    fprintf(out, "\n==================================================================\n");
    fprintf(out, "                      SCAN SUMMARY\n");
    fprintf(out, "==================================================================\n");
    fprintf(out, "  Total targets scanned: %d\n", s->count);
    
    fprintf(out, "  IDOR CONFIRMED:        %s%d%s\n", s->total_idor > 0 ? red : "", s->total_idor, s->total_idor > 0 ? reset : "");
    fprintf(out, "  DENIED (safe):         %s%d%s\n", green, s->total_denied, reset);
    fprintf(out, "  Safe (remapped):       %s%d%s\n", green, s->total_safe, reset);
    fprintf(out, "  Ambiguous:             %s%d%s\n", yellow, s->total_ambiguous, reset);
    fprintf(out, "  Not JSON:              %s%d%s\n", yellow, s->total_not_json, reset);
    fprintf(out, "==================================================================\n");
}

static void escape_json_string(FILE *out, const char *str) {
    if (!str) return;
    for (const char *p = str; *p; p++) {
        switch (*p) {
            case '"': fprintf(out, "\\\""); break;
            case '\\': fprintf(out, "\\\\"); break;
            case '\b': fprintf(out, "\\b"); break;
            case '\f': fprintf(out, "\\f"); break;
            case '\n': fprintf(out, "\\n"); break;
            case '\r': fprintf(out, "\\r"); break;
            case '\t': fprintf(out, "\\t"); break;
            default:
                if (*p >= 0x00 && *p <= 0x1f) {
                    fprintf(out, "\\u%04x", (int)*p);
                } else {
                    fputc(*p, out);
                }
        }
    }
}

void report_write_json(FILE *out, const scan_summary_t *s) {
    fprintf(out, "{\n");
    fprintf(out, "  \"idor_prober_version\": \"2.0\",\n");
    fprintf(out, "  \"summary\": {\n");
    fprintf(out, "    \"total\": %d,\n", s->count);
    fprintf(out, "    \"idor_confirmed\": %d,\n", s->total_idor);
    fprintf(out, "    \"denied\": %d,\n", s->total_denied);
    fprintf(out, "    \"safe_remapped\": %d,\n", s->total_safe);
    fprintf(out, "    \"ambiguous\": %d,\n", s->total_ambiguous);
    fprintf(out, "    \"not_json\": %d\n", s->total_not_json);
    fprintf(out, "  },\n");
    fprintf(out, "  \"results\": [\n");
    for (int i = 0; i < s->count; i++) {
        const scan_result_t *r = &s->results[i];
        fprintf(out, "    {\n");
        fprintf(out, "      \"url\": \"");
        escape_json_string(out, r->url);
        fprintf(out, "\",\n");
        fprintf(out, "      \"method\": \"");
        escape_json_string(out, r->method);
        fprintf(out, "\",\n");
        fprintf(out, "      \"verdict\": \"%s\",\n", verdict_to_str(r->diff.verdict));
        fprintf(out, "      \"confidence\": %d,\n", r->diff.confidence);
        fprintf(out, "      \"status_a\": %ld,\n", r->status_a);
        fprintf(out, "      \"status_b_cross\": %ld,\n", r->status_b_cross);
        fprintf(out, "      \"cross_similarity\": %.4f,\n", r->diff.cross_similarity);
        fprintf(out, "      \"shape_similarity\": %.4f,\n", r->diff.shape_similarity);
        fprintf(out, "      \"value_similarity\": %.4f,\n", r->diff.value_similarity);
        if (r->have_baseline) {
            fprintf(out, "      \"baseline_similarity\": %.4f,\n", r->diff.baseline_similarity);
        } else {
            fprintf(out, "      \"baseline_similarity\": null,\n");
        }
        fprintf(out, "      \"reason\": \"");
        escape_json_string(out, r->diff.reason);
        fprintf(out, "\",\n");
        fprintf(out, "      \"missing_security_headers\": [");
        for (int j = 0; j < r->hdr.missing_count; j++) {
            fprintf(out, "\"%s\"", r->hdr.missing_headers[j]);
            if (j < r->hdr.missing_count - 1) fprintf(out, ", ");
        }
        fprintf(out, "],\n");
        fprintf(out, "      \"cache_concern\": %s\n", r->hdr.cache_concern ? "true" : "false");
        fprintf(out, "    }%s\n", i < s->count - 1 ? "," : "");
    }
    fprintf(out, "  ]\n");
    fprintf(out, "}\n");
}

static void escape_html(FILE *out, const char *str) {
    if (!str) return;
    for (const char *p = str; *p; p++) {
        switch (*p) {
            case '&': fprintf(out, "&amp;"); break;
            case '<': fprintf(out, "&lt;"); break;
            case '>': fprintf(out, "&gt;"); break;
            case '"': fprintf(out, "&quot;"); break;
            case '\'': fprintf(out, "&#39;"); break;
            default: fputc(*p, out);
        }
    }
}

void report_write_html(FILE *out, const scan_summary_t *s) {
    time_t now = time(NULL);
    char *time_str = ctime(&now);
    if (time_str) {
        time_str[strlen(time_str) - 1] = '\0';
    } else {
        time_str = "Unknown";
    }

    fprintf(out, "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n");
    fprintf(out, "  <meta charset=\"UTF-8\">\n");
    fprintf(out, "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n");
    fprintf(out, "  <title>IDOR Prober v2.0 - Scan Report</title>\n");
    fprintf(out, "  <style>\n");
    fprintf(out, "    :root { --bg: #0f172a; --card-bg: #1e293b; --text: #e2e8f0; --text-muted: #94a3b8; --border: #334155; --primary: #3b82f6; --red: #ef4444; --green: #22c55e; --yellow: #eab308; }\n");
    fprintf(out, "    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: var(--bg); color: var(--text); margin: 0; padding: 20px; line-height: 1.5; }\n");
    fprintf(out, "    .container { max-width: 1400px; margin: 0 auto; }\n");
    fprintf(out, "    header { margin-bottom: 30px; border-bottom: 1px solid var(--border); padding-bottom: 20px; }\n");
    fprintf(out, "    h1 { margin: 0 0 10px 0; color: #fff; }\n");
    fprintf(out, "    .meta { color: var(--text-muted); font-size: 0.9em; }\n");
    fprintf(out, "    .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 30px; }\n");
    fprintf(out, "    .stat-card { background: var(--card-bg); border-radius: 8px; padding: 20px; border-left: 4px solid var(--border); box-shadow: 0 4px 6px rgba(0,0,0,0.1); }\n");
    fprintf(out, "    .stat-card.red { border-left-color: var(--red); }\n");
    fprintf(out, "    .stat-card.green { border-left-color: var(--green); }\n");
    fprintf(out, "    .stat-card.yellow { border-left-color: var(--yellow); }\n");
    fprintf(out, "    .stat-value { font-size: 2em; font-weight: bold; margin-bottom: 5px; }\n");
    fprintf(out, "    .stat-label { color: var(--text-muted); font-size: 0.9em; text-transform: uppercase; letter-spacing: 0.5px; }\n");
    fprintf(out, "    table { width: 100%%; border-collapse: collapse; background: var(--card-bg); border-radius: 8px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }\n");
    fprintf(out, "    th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid var(--border); }\n");
    fprintf(out, "    th { background: rgba(255,255,255,0.05); font-weight: 600; cursor: pointer; user-select: none; }\n");
    fprintf(out, "    th:hover { background: rgba(255,255,255,0.1); }\n");
    fprintf(out, "    tr:last-child td { border-bottom: none; }\n");
    fprintf(out, "    tr:hover td { background: rgba(255,255,255,0.02); }\n");
    fprintf(out, "    .badge { padding: 4px 8px; border-radius: 4px; font-size: 0.85em; font-weight: bold; display: inline-block; }\n");
    fprintf(out, "    .badge-red { background: rgba(239,68,68,0.2); color: #fca5a5; }\n");
    fprintf(out, "    .badge-green { background: rgba(34,197,94,0.2); color: #86efac; }\n");
    fprintf(out, "    .badge-yellow { background: rgba(234,179,8,0.2); color: #fde047; }\n");
    fprintf(out, "    .url-cell { max-width: 300px; word-break: break-all; }\n");
    fprintf(out, "    .reason-cell { max-width: 300px; font-size: 0.9em; color: var(--text-muted); }\n");
    fprintf(out, "  </style>\n");
    fprintf(out, "</head>\n<body>\n");
    fprintf(out, "<div class=\"container\">\n");
    fprintf(out, "  <header>\n");
    fprintf(out, "    <h1>IDOR Prober v2.0 - Scan Report</h1>\n");
    fprintf(out, "    <div class=\"meta\">Generated on: %s</div>\n", time_str);
    fprintf(out, "  </header>\n");
    
    fprintf(out, "  <div class=\"stats-grid\">\n");
    fprintf(out, "    <div class=\"stat-card\">\n");
    fprintf(out, "      <div class=\"stat-value\">%d</div>\n", s->count);
    fprintf(out, "      <div class=\"stat-label\">Total Targets</div>\n");
    fprintf(out, "    </div>\n");
    fprintf(out, "    <div class=\"stat-card red\">\n");
    fprintf(out, "      <div class=\"stat-value\">%d</div>\n", s->total_idor);
    fprintf(out, "      <div class=\"stat-label\">IDOR Confirmed</div>\n");
    fprintf(out, "    </div>\n");
    fprintf(out, "    <div class=\"stat-card green\">\n");
    fprintf(out, "      <div class=\"stat-value\">%d</div>\n", s->total_denied);
    fprintf(out, "      <div class=\"stat-label\">Denied (Safe)</div>\n");
    fprintf(out, "    </div>\n");
    fprintf(out, "    <div class=\"stat-card green\">\n");
    fprintf(out, "      <div class=\"stat-value\">%d</div>\n", s->total_safe);
    fprintf(out, "      <div class=\"stat-label\">Safe Remapped</div>\n");
    fprintf(out, "    </div>\n");
    fprintf(out, "    <div class=\"stat-card yellow\">\n");
    fprintf(out, "      <div class=\"stat-value\">%d</div>\n", s->total_ambiguous);
    fprintf(out, "      <div class=\"stat-label\">Ambiguous</div>\n");
    fprintf(out, "    </div>\n");
    fprintf(out, "  </div>\n");
    
    fprintf(out, "  <table id=\"resultsTable\">\n");
    fprintf(out, "    <thead>\n");
    fprintf(out, "      <tr>\n");
    fprintf(out, "        <th onclick=\"sortTable(0)\">URL <span></span></th>\n");
    fprintf(out, "        <th onclick=\"sortTable(1)\">Method <span></span></th>\n");
    fprintf(out, "        <th onclick=\"sortTable(2)\">Verdict <span></span></th>\n");
    fprintf(out, "        <th onclick=\"sortTable(3)\">Conf. %% <span></span></th>\n");
    fprintf(out, "        <th onclick=\"sortTable(4)\">Status A <span></span></th>\n");
    fprintf(out, "        <th onclick=\"sortTable(5)\">Status B <span></span></th>\n");
    fprintf(out, "        <th onclick=\"sortTable(6)\">Cross Sim. <span></span></th>\n");
    fprintf(out, "        <th>Reason</th>\n");
    fprintf(out, "      </tr>\n");
    fprintf(out, "    </thead>\n");
    fprintf(out, "    <tbody>\n");
    
    for (int i = 0; i < s->count; i++) {
        const scan_result_t *r = &s->results[i];
        const char *vstr = verdict_to_str(r->diff.verdict);
        const char *badge_class = "badge-yellow";
        if (r->diff.verdict == VERDICT_IDOR_CONFIRMED) badge_class = "badge-red";
        else if (r->diff.verdict == VERDICT_DENIED || r->diff.verdict == VERDICT_SAFE_REMAPPED) badge_class = "badge-green";
        
        fprintf(out, "      <tr>\n");
        fprintf(out, "        <td class=\"url-cell\">");
        escape_html(out, r->url);
        fprintf(out, "</td>\n");
        fprintf(out, "        <td>%s</td>\n", r->method);
        fprintf(out, "        <td><span class=\"badge %s\">%s</span></td>\n", badge_class, vstr);
        fprintf(out, "        <td>%d</td>\n", r->diff.confidence);
        fprintf(out, "        <td>%ld</td>\n", r->status_a);
        fprintf(out, "        <td>%ld</td>\n", r->status_b_cross);
        fprintf(out, "        <td>%.2f</td>\n", r->diff.cross_similarity);
        fprintf(out, "        <td class=\"reason-cell\">");
        escape_html(out, r->diff.reason);
        fprintf(out, "</td>\n");
        fprintf(out, "      </tr>\n");
    }
    
    fprintf(out, "    </tbody>\n");
    fprintf(out, "  </table>\n");
    fprintf(out, "</div>\n");
    
    fprintf(out, "<script>\n");
    fprintf(out, "function sortTable(n) {\n");
    fprintf(out, "  var table, rows, switching, i, x, y, shouldSwitch, dir, switchcount = 0;\n");
    fprintf(out, "  table = document.getElementById(\"resultsTable\");\n");
    fprintf(out, "  switching = true;\n");
    fprintf(out, "  dir = \"asc\";\n");
    fprintf(out, "  while (switching) {\n");
    fprintf(out, "    switching = false;\n");
    fprintf(out, "    rows = table.rows;\n");
    fprintf(out, "    for (i = 1; i < (rows.length - 1); i++) {\n");
    fprintf(out, "      shouldSwitch = false;\n");
    fprintf(out, "      x = rows[i].getElementsByTagName(\"TD\")[n];\n");
    fprintf(out, "      y = rows[i + 1].getElementsByTagName(\"TD\")[n];\n");
    fprintf(out, "      var xContent = x.innerText || x.textContent;\n");
    fprintf(out, "      var yContent = y.innerText || y.textContent;\n");
    fprintf(out, "      var cmpX = isNaN(parseFloat(xContent)) ? xContent.toLowerCase() : parseFloat(xContent);\n");
    fprintf(out, "      var cmpY = isNaN(parseFloat(yContent)) ? yContent.toLowerCase() : parseFloat(yContent);\n");
    fprintf(out, "      if (dir == \"asc\") {\n");
    fprintf(out, "        if (cmpX > cmpY) { shouldSwitch = true; break; }\n");
    fprintf(out, "      } else if (dir == \"desc\") {\n");
    fprintf(out, "        if (cmpX < cmpY) { shouldSwitch = true; break; }\n");
    fprintf(out, "      }\n");
    fprintf(out, "    }\n");
    fprintf(out, "    if (shouldSwitch) {\n");
    fprintf(out, "      rows[i].parentNode.insertBefore(rows[i + 1], rows[i]);\n");
    fprintf(out, "      switching = true;\n");
    fprintf(out, "      switchcount++;\n");
    fprintf(out, "    } else {\n");
    fprintf(out, "      if (switchcount == 0 && dir == \"asc\") {\n");
    fprintf(out, "        dir = \"desc\";\n");
    fprintf(out, "        switching = true;\n");
    fprintf(out, "      }\n");
    fprintf(out, "    }\n");
    fprintf(out, "  }\n");
    fprintf(out, "}\n");
    fprintf(out, "</script>\n");
    fprintf(out, "</body>\n</html>\n");
}
