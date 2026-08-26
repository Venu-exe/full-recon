#include "header_analysis.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

static char *extract_header_value(const char *headers, const char *header_name) {
    if (!headers || !header_name) return NULL;
    char search[128];
    snprintf(search, sizeof(search), "\n%s:", header_name);
    
    const char *start = strcasestr(headers, search);
    if (!start) {
        snprintf(search, sizeof(search), "%s:", header_name);
        if (strncasecmp(headers, search, strlen(search)) == 0) {
            start = headers;
        } else {
            return NULL;
        }
    } else {
        start++; /* skip newline */
    }
    
    start += strlen(header_name) + 1;
    while (*start == ' ' || *start == '\t') start++;
    
    const char *end = strchr(start, '\r');
    if (!end) end = strchr(start, '\n');
    if (!end) end = start + strlen(start);
    
    size_t len = end - start;
    char *val = malloc(len + 1);
    if (val) {
        strncpy(val, start, len);
        val[len] = '\0';
    }
    return val;
}

void analyze_response_headers(const char *headers_a, const char *headers_b_cross, header_analysis_t *out) {
    memset(out, 0, sizeof(header_analysis_t));
    if (!headers_b_cross) return;

    const char *sec_headers[] = {
        "X-Content-Type-Options",
        "X-Frame-Options",
        "Strict-Transport-Security",
        "Content-Security-Policy",
        "X-XSS-Protection",
        "Cache-Control"
    };

    for (size_t i = 0; i < sizeof(sec_headers)/sizeof(sec_headers[0]); i++) {
        char *val = extract_header_value(headers_b_cross, sec_headers[i]);
        if (!val) {
            if (out->missing_count < MAX_MISSING_HEADERS) {
                strncpy(out->missing_headers[out->missing_count], sec_headers[i], sizeof(out->missing_headers[0]) - 1);
                out->missing_count++;
            }
        } else {
            free(val);
        }
    }

    char *cc = extract_header_value(headers_b_cross, "Cache-Control");
    if (!cc) {
        out->cache_concern = 1;
        snprintf(out->cache_note, sizeof(out->cache_note), "Cache-Control missing, potential cache leak.");
    } else {
        char *cc_lower = strdup(cc);
        for (char *p = cc_lower; *p; p++) *p = tolower(*p);
        
        if (strstr(cc_lower, "public") || !strstr(cc_lower, "no-store")) {
            out->cache_concern = 1;
            snprintf(out->cache_note, sizeof(out->cache_note), "Cache-Control allows caching, potential data leak.");
        }
        free(cc_lower);
        free(cc);
    }

    if (headers_a) {
        char *ct_a = extract_header_value(headers_a, "Content-Type");
        char *ct_b = extract_header_value(headers_b_cross, "Content-Type");
        char *cl_a = extract_header_value(headers_a, "Content-Length");
        char *cl_b = extract_header_value(headers_b_cross, "Content-Length");

        int ct_match = (ct_a && ct_b && strcmp(ct_a, ct_b) == 0);
        int cl_match = (cl_a && cl_b && strcmp(cl_a, cl_b) == 0);

        if (ct_match && cl_match) {
            out->headers_match = 1;
            snprintf(out->header_note, sizeof(out->header_note), "Content-Type and Content-Length match exactly.");
        }

        if (ct_a) free(ct_a);
        if (ct_b) free(ct_b);
        if (cl_a) free(cl_a);
        if (cl_b) free(cl_b);
    }
}
