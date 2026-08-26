#ifndef HEADER_ANALYSIS_H
#define HEADER_ANALYSIS_H

#define MAX_MISSING_HEADERS 8
#define MAX_HEADER_NOTE 256

typedef struct {
    int missing_count;
    char missing_headers[MAX_MISSING_HEADERS][64];  /* names of missing security headers */
    int cache_concern;                               /* 1 if caching headers suggest shared/leaked data */
    char cache_note[MAX_HEADER_NOTE];
    int headers_match;                               /* 1 if response headers between A and B are suspiciously similar */
    char header_note[MAX_HEADER_NOTE];
} header_analysis_t;

/* Analyze response headers from user A's request and user B's cross-account request.
 * headers_a and headers_b_cross are raw header strings as returned by libcurl. */
void analyze_response_headers(const char *headers_a, const char *headers_b_cross, header_analysis_t *out);

#endif
