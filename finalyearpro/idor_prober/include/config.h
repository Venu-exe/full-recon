#ifndef CONFIG_H
#define CONFIG_H

typedef enum {
    REPORT_TEXT,
    REPORT_JSON,
    REPORT_HTML
} report_format_t;

typedef struct {
    char *session_a_path;
    char *session_b_path;
    char *single_url;
    char *baseline_url;
    char *list_path;
    char *baseline_list_path;
    char *out_path;
    char *method;           /* GET, POST, PUT, DELETE, PATCH */
    char *body;             /* request body for POST/PUT/PATCH */
    char *content_type;     /* content-type header for body */
    char *enum_range;       /* e.g. "1-100" for ID enumeration */
    int verbose;
    int threads;            /* number of threads, default 4 */
    double rate_limit;      /* requests per second, 0 = unlimited */
    int use_color;          /* 1 = colored output */
    report_format_t format;
} config_t;

/* Initialize config with defaults */
void config_init(config_t *cfg);

/* Load config from a simple key=value file.
 * Lines starting with # are comments. Blank lines are ignored.
 * Supported keys: session_a, session_b, url, baseline_url, url_list, baseline_list,
 *                 output, method, body, content_type, enum_range, verbose, threads,
 *                 rate_limit, color, format
 * Returns 0 on success, -1 on error. */
int config_load_from_file(const char *path, config_t *cfg);

void config_free(config_t *cfg);

#endif
