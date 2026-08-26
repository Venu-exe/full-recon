/*
 * idor_prober v2.0 - dual-session access control prober
 *
 * Probes web application endpoints for Insecure Direct Object Reference (IDOR)
 * vulnerabilities by comparing responses across authenticated sessions.
 *
 * For authorized security testing only. Only use against systems you own or
 * have explicit written permission to test.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>

#include "http_client.h"
#include "json_diff.h"
#include "reporter.h"
#include "header_analysis.h"
#include "thread_pool.h"
#include "rate_limit.h"
#include "config.h"

#define VERSION "2.0"

/* ---------- shared scan context ---------- */

typedef struct {
    const session_t *sess_a;
    const session_t *sess_b;
    http_method_t method;
    const char *body;
    const char *content_type;
    int verbose;
    int use_color;
    rate_limiter_t *limiter;
    scan_summary_t *summary;
    pthread_mutex_t *summary_lock;
    pthread_mutex_t *print_lock;
    FILE *report;
    report_format_t format;
    int *progress_current;
    int progress_total;
} scan_ctx_t;

typedef struct {
    char *url;
    char *baseline_url;
    scan_ctx_t *ctx;
} scan_task_t;

/* ---------- helpers ---------- */

static void print_usage(const char *prog) {
    fprintf(stderr,
        "idor_prober v" VERSION " - dual-session access control prober\n"
        "\n"
        "Usage:\n"
        "  %s -A <sessionA.txt> -B <sessionB.txt> -u <url> [options]\n"
        "  %s -A <sessionA.txt> -B <sessionB.txt> -l <urls.txt> [options]\n"
        "  %s -A <sessionA.txt> -B <sessionB.txt> -u <url_template> -e <range> [options]\n"
        "  %s -c <config.txt> [options]\n"
        "\n"
        "Session file format (one directive per line):\n"
        "  Cookie: session=abc123; other=value\n"
        "  Authorization: Bearer eyJ...\n"
        "  Header: X-Api-Key: value\n"
        "\n"
        "Core options:\n"
        "  -u   single target URL (A's resource, e.g. /user/1234/profile)\n"
        "  -l   file of target URLs, one per line\n"
        "  -b   B's own equivalent resource URL for baseline comparison\n"
        "  -L   file of B's baseline URLs, aligned line-by-line with -l\n"
        "\n"
        "v2.0 options:\n"
        "  -m   HTTP method: GET (default), POST, PUT, DELETE, PATCH\n"
        "  -d   request body (for POST/PUT/PATCH)\n"
        "  -T   content-type for request body (default: application/json)\n"
        "  -e   ID enumeration range, e.g. 1-100 (use {ID} in -u URL template)\n"
        "  -t   number of threads (default: 4, use 1 for sequential)\n"
        "  -r   rate limit: max requests per second (default: unlimited)\n"
        "  -f   report format: text (default), json, html\n"
        "  -c   load options from config file\n"
        "  -C   disable colored output\n"
        "\n"
        "General options:\n"
        "  -o   write report to file instead of stdout\n"
        "  -v   verbose: include response body previews and header analysis\n"
        "  -h   show this help message\n"
        "\n"
        "ID enumeration example:\n"
        "  %s -A sess_a.txt -B sess_b.txt -u 'http://api/user/{ID}/profile' -e 1-50 -t 8\n"
        "\n"
        "Config file example:\n"
        "  session_a = sess_a.txt\n"
        "  session_b = sess_b.txt\n"
        "  url = http://api/user/1001/profile\n"
        "  method = GET\n"
        "  threads = 8\n"
        "  rate_limit = 10\n"
        "  format = json\n"
        "\n"
        "This tool is for authorized security testing only.\n",
        prog, prog, prog, prog, prog);
}

static char *read_line_n(FILE *f) {
    char buf[4096];
    if (!fgets(buf, sizeof(buf), f)) return NULL;
    size_t len = strlen(buf);
    while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r')) buf[--len] = '\0';
    if (len == 0) return NULL;
    return strdup(buf);
}

static void truncate_for_preview(const char *s, char *out, size_t outlen) {
    if (!s || !s[0]) { out[0] = '\0'; return; }
    size_t len = strlen(s);
    if (len < outlen - 4) {
        snprintf(out, outlen, "%s", s);
    } else {
        memcpy(out, s, outlen - 4);
        strcpy(out + outlen - 4, "...");
    }
}

/* ---------- core probe logic ---------- */

static void run_one(const char *url, const char *baseline_url,
                     scan_ctx_t *ctx, scan_result_t *result) {
    http_response_t resp_a = {0}, resp_b_cross = {0}, resp_b_own = {0};
    int have_baseline = 0;

    memset(result, 0, sizeof(*result));
    snprintf(result->url, sizeof(result->url), "%s", url);
    if (baseline_url) snprintf(result->baseline_url, sizeof(result->baseline_url), "%s", baseline_url);
    snprintf(result->method, sizeof(result->method), "%s", http_method_to_str(ctx->method));

    /* Rate limit before each request burst */
    rate_limiter_wait(ctx->limiter);

    /* Fetch as User A */
    if (http_fetch_ex(url, ctx->sess_a, ctx->method, ctx->body, ctx->content_type, &resp_a) != 0) {
        result->diff.verdict = VERDICT_AMBIGUOUS;
        result->diff.confidence = 0;
        snprintf(result->diff.reason, sizeof(result->diff.reason),
                 "Failed to fetch as User A -- skipping.");
        return;
    }

    rate_limiter_wait(ctx->limiter);

    /* Fetch as User B (cross-account) */
    if (http_fetch_ex(url, ctx->sess_b, ctx->method, ctx->body, ctx->content_type, &resp_b_cross) != 0) {
        result->diff.verdict = VERDICT_AMBIGUOUS;
        result->diff.confidence = 0;
        snprintf(result->diff.reason, sizeof(result->diff.reason),
                 "Failed to fetch as User B -- skipping.");
        http_response_free(&resp_a);
        return;
    }

    /* Fetch B's own baseline if provided */
    if (baseline_url && baseline_url[0]) {
        rate_limiter_wait(ctx->limiter);
        if (http_fetch_ex(baseline_url, ctx->sess_b, ctx->method, ctx->body, ctx->content_type, &resp_b_own) == 0) {
            have_baseline = 1;
        }
    }

    /* Populate result metadata */
    result->status_a = resp_a.status_code;
    result->status_b_cross = resp_b_cross.status_code;
    result->time_a = resp_a.time_total;
    result->time_b_cross = resp_b_cross.time_total;
    result->body_len_a = resp_a.body_len;
    result->body_len_b_cross = resp_b_cross.body_len;
    result->have_baseline = have_baseline;

    if (have_baseline) {
        result->status_b_own = resp_b_own.status_code;
        result->time_b_own = resp_b_own.time_total;
        result->body_len_b_own = resp_b_own.body_len;
    }

    /* JSON diffing and IDOR classification */
    classify_idor(resp_a.body, resp_b_cross.body,
                  have_baseline ? resp_b_own.body : NULL,
                  resp_b_cross.status_code, &result->diff);

    /* Response header analysis */
    analyze_response_headers(resp_a.headers_raw, resp_b_cross.headers_raw, &result->hdr);

    /* Body previews for verbose mode */
    truncate_for_preview(resp_a.body, result->body_a_preview, sizeof(result->body_a_preview));
    truncate_for_preview(resp_b_cross.body, result->body_b_cross_preview, sizeof(result->body_b_cross_preview));
    if (have_baseline) {
        truncate_for_preview(resp_b_own.body, result->body_b_own_preview, sizeof(result->body_b_own_preview));
    }

    /* Print IDOR alerts to stderr immediately */
    if (result->diff.verdict == VERDICT_IDOR_CONFIRMED) {
        fprintf(stderr, "[!!] IDOR CONFIRMED: %s [%s] (confidence %d%%)\n",
                url, http_method_to_str(ctx->method), result->diff.confidence);
    }

    http_response_free(&resp_a);
    http_response_free(&resp_b_cross);
    if (have_baseline) http_response_free(&resp_b_own);
}

/* ---------- threaded task wrapper ---------- */

static void scan_task_worker(void *arg) {
    scan_task_t *task = (scan_task_t *)arg;
    scan_ctx_t *ctx = task->ctx;

    scan_result_t result;
    run_one(task->url, task->baseline_url, ctx, &result);

    /* Thread-safe: add to summary and print result */
    pthread_mutex_lock(ctx->summary_lock);
    summary_add(ctx->summary, &result);
    (*(ctx->progress_current))++;
    int cur = *(ctx->progress_current);
    pthread_mutex_unlock(ctx->summary_lock);

    /* Print result in real-time for text format */
    if (ctx->format == REPORT_TEXT) {
        pthread_mutex_lock(ctx->print_lock);
        report_print_result(ctx->report, &result, ctx->verbose, ctx->use_color);
        pthread_mutex_unlock(ctx->print_lock);
    }

    /* Progress bar */
    if (ctx->use_color && ctx->format == REPORT_TEXT) {
        report_progress(cur, ctx->progress_total, ctx->use_color);
    }

    free(task->url);
    free(task->baseline_url);
    free(task);
}

/* ---------- ID enumeration ---------- */

static int parse_enum_range(const char *range, int *start, int *end) {
    if (!range) return -1;
    if (sscanf(range, "%d-%d", start, end) == 2 && *start <= *end) return 0;
    return -1;
}

static char *expand_url_template(const char *tmpl, int id) {
    const char *marker = strstr(tmpl, "{ID}");
    if (!marker) return strdup(tmpl);

    size_t prefix_len = marker - tmpl;
    char id_str[32];
    snprintf(id_str, sizeof(id_str), "%d", id);
    size_t id_len = strlen(id_str);
    size_t suffix_len = strlen(marker + 4);

    char *result = malloc(prefix_len + id_len + suffix_len + 1);
    if (!result) return NULL;
    memcpy(result, tmpl, prefix_len);
    memcpy(result + prefix_len, id_str, id_len);
    memcpy(result + prefix_len + id_len, marker + 4, suffix_len + 1);
    return result;
}

/* ---------- main ---------- */

int main(int argc, char **argv) {
    config_t cfg;
    config_init(&cfg);

    int opt;
    while ((opt = getopt(argc, argv, "A:B:u:b:l:L:o:m:d:T:e:t:r:f:c:Cvh")) != -1) {
        switch (opt) {
            case 'A': free(cfg.session_a_path); cfg.session_a_path = strdup(optarg); break;
            case 'B': free(cfg.session_b_path); cfg.session_b_path = strdup(optarg); break;
            case 'u': free(cfg.single_url); cfg.single_url = strdup(optarg); break;
            case 'b': free(cfg.baseline_url); cfg.baseline_url = strdup(optarg); break;
            case 'l': free(cfg.list_path); cfg.list_path = strdup(optarg); break;
            case 'L': free(cfg.baseline_list_path); cfg.baseline_list_path = strdup(optarg); break;
            case 'o': free(cfg.out_path); cfg.out_path = strdup(optarg); break;
            case 'm': free(cfg.method); cfg.method = strdup(optarg); break;
            case 'd': free(cfg.body); cfg.body = strdup(optarg); break;
            case 'T': free(cfg.content_type); cfg.content_type = strdup(optarg); break;
            case 'e': free(cfg.enum_range); cfg.enum_range = strdup(optarg); break;
            case 't': cfg.threads = atoi(optarg); break;
            case 'r': cfg.rate_limit = atof(optarg); break;
            case 'f':
                if (strcasecmp(optarg, "json") == 0) cfg.format = REPORT_JSON;
                else if (strcasecmp(optarg, "html") == 0) cfg.format = REPORT_HTML;
                else cfg.format = REPORT_TEXT;
                break;
            case 'c':
                if (config_load_from_file(optarg, &cfg) != 0) {
                    fprintf(stderr, "[!] Failed to load config: %s\n", optarg);
                    return 1;
                }
                break;
            case 'C': cfg.use_color = 0; break;
            case 'v': cfg.verbose = 1; break;
            case 'h':
                print_usage(argv[0]);
                config_free(&cfg);
                return 0;
            default:
                print_usage(argv[0]);
                config_free(&cfg);
                return 1;
        }
    }

    /* Validate required options */
    if (!cfg.session_a_path || !cfg.session_b_path) {
        fprintf(stderr, "[!] Both -A and -B session files are required.\n\n");
        print_usage(argv[0]);
        config_free(&cfg);
        return 1;
    }
    if (!cfg.single_url && !cfg.list_path) {
        fprintf(stderr, "[!] Either -u (single URL) or -l (URL list) is required.\n\n");
        print_usage(argv[0]);
        config_free(&cfg);
        return 1;
    }

    /* Parse HTTP method */
    http_method_t method = HTTP_GET;
    if (cfg.method && http_method_from_str(cfg.method, &method) != 0) {
        fprintf(stderr, "[!] Unknown HTTP method: %s\n", cfg.method);
        config_free(&cfg);
        return 1;
    }

    /* Clamp thread count */
    if (cfg.threads < 1) cfg.threads = 1;
    if (cfg.threads > 64) cfg.threads = 64;

    /* Load sessions */
    session_t sess_a, sess_b;
    if (session_load_from_file(cfg.session_a_path, &sess_a) != 0) {
        config_free(&cfg);
        return 1;
    }
    if (session_load_from_file(cfg.session_b_path, &sess_b) != 0) {
        session_free(&sess_a);
        config_free(&cfg);
        return 1;
    }

    if (http_client_global_init() != 0) {
        fprintf(stderr, "[!] Failed to init HTTP client\n");
        session_free(&sess_a);
        session_free(&sess_b);
        config_free(&cfg);
        return 1;
    }

    /* Open output file */
    FILE *report = stdout;
    if (cfg.out_path) {
        report = fopen(cfg.out_path, "w");
        if (!report) {
            fprintf(stderr, "[!] Could not open output file: %s\n", cfg.out_path);
            session_free(&sess_a);
            session_free(&sess_b);
            http_client_global_cleanup();
            config_free(&cfg);
            return 1;
        }
    }

    /* Create rate limiter */
    rate_limiter_t *limiter = rate_limiter_create(cfg.rate_limit);

    /* Initialize summary and locks */
    scan_summary_t summary;
    summary_init(&summary);
    pthread_mutex_t summary_lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_t print_lock = PTHREAD_MUTEX_INITIALIZER;
    int progress_current = 0;

    /* Build scan context */
    scan_ctx_t ctx = {
        .sess_a = &sess_a,
        .sess_b = &sess_b,
        .method = method,
        .body = cfg.body,
        .content_type = cfg.content_type,
        .verbose = cfg.verbose,
        .use_color = cfg.use_color,
        .limiter = limiter,
        .summary = &summary,
        .summary_lock = &summary_lock,
        .print_lock = &print_lock,
        .report = report,
        .format = cfg.format,
        .progress_current = &progress_current,
        .progress_total = 0
    };

    /* Print header for text format */
    if (cfg.format == REPORT_TEXT) {
        fprintf(report, "idor_prober v" VERSION " report\n");
        if (cfg.rate_limit > 0) {
            fprintf(report, "Method: %s | Threads: %d | Rate limit: %.1f req/s\n",
                    http_method_to_str(method), cfg.threads, cfg.rate_limit);
        } else {
            fprintf(report, "Method: %s | Threads: %d | Rate limit: unlimited\n",
                    http_method_to_str(method), cfg.threads);
        }
        fprintf(report, "Authorized security testing only.\n\n");
    }

    /* Create thread pool */
    thread_pool_t *pool = thread_pool_create(cfg.threads);
    if (!pool) {
        fprintf(stderr, "[!] Failed to create thread pool\n");
        goto cleanup;
    }

    /* ---------- build target list and submit tasks ---------- */

    if (cfg.enum_range && cfg.single_url) {
        /* ID enumeration mode */
        int start_id, end_id;
        if (parse_enum_range(cfg.enum_range, &start_id, &end_id) != 0) {
            fprintf(stderr, "[!] Invalid enumeration range: %s (expected format: START-END)\n", cfg.enum_range);
            thread_pool_destroy(pool);
            goto cleanup;
        }

        ctx.progress_total = end_id - start_id + 1;
        if (cfg.use_color && cfg.format == REPORT_TEXT) {
            fprintf(stderr, "[*] Enumerating IDs %d-%d on %s (%d targets)\n",
                    start_id, end_id, cfg.single_url, ctx.progress_total);
        }

        for (int id = start_id; id <= end_id; id++) {
            scan_task_t *task = calloc(1, sizeof(scan_task_t));
            task->url = expand_url_template(cfg.single_url, id);
            task->baseline_url = cfg.baseline_url ? expand_url_template(cfg.baseline_url, id) : NULL;
            task->ctx = &ctx;
            thread_pool_submit(pool, scan_task_worker, task);
        }

    } else if (cfg.single_url) {
        /* Single URL mode */
        ctx.progress_total = 1;
        scan_task_t *task = calloc(1, sizeof(scan_task_t));
        task->url = strdup(cfg.single_url);
        task->baseline_url = cfg.baseline_url ? strdup(cfg.baseline_url) : NULL;
        task->ctx = &ctx;
        thread_pool_submit(pool, scan_task_worker, task);

    } else {
        /* URL list mode */
        FILE *lf = fopen(cfg.list_path, "r");
        if (!lf) {
            fprintf(stderr, "[!] Could not open URL list: %s\n", cfg.list_path);
            thread_pool_destroy(pool);
            goto cleanup;
        }
        FILE *blf = cfg.baseline_list_path ? fopen(cfg.baseline_list_path, "r") : NULL;

        /* First pass: count lines for progress */
        char countbuf[4096];
        int total = 0;
        while (fgets(countbuf, sizeof(countbuf), lf)) {
            size_t len = strlen(countbuf);
            while (len > 0 && (countbuf[len-1] == '\n' || countbuf[len-1] == '\r')) countbuf[--len] = '\0';
            if (len > 0) total++;
        }
        rewind(lf);
        ctx.progress_total = total;

        if (cfg.use_color && cfg.format == REPORT_TEXT) {
            fprintf(stderr, "[*] Loaded %d targets, scanning with %d threads\n", total, cfg.threads);
        }

        char *url;
        while ((url = read_line_n(lf)) != NULL) {
            char *burl = blf ? read_line_n(blf) : NULL;
            scan_task_t *task = calloc(1, sizeof(scan_task_t));
            task->url = url;
            task->baseline_url = burl;
            task->ctx = &ctx;
            thread_pool_submit(pool, scan_task_worker, task);
        }

        fclose(lf);
        if (blf) fclose(blf);
    }

    /* Wait for all tasks to complete */
    thread_pool_wait(pool);
    thread_pool_destroy(pool);

    /* Clear progress bar */
    if (cfg.use_color && cfg.format == REPORT_TEXT && ctx.progress_total > 1) {
        fprintf(stderr, "\r%80s\r", "");
    }

    /* ---------- generate final report ---------- */

    switch (cfg.format) {
        case REPORT_JSON:
            report_write_json(report, &summary);
            break;
        case REPORT_HTML:
            report_write_html(report, &summary);
            break;
        case REPORT_TEXT:
        default:
            report_print_summary(report, &summary, cfg.use_color);
            break;
    }

cleanup:
    if (cfg.out_path && report) {
        fclose(report);
        if (cfg.use_color) {
            fprintf(stderr, "[*] Report written to %s\n", cfg.out_path);
        }
    }
    summary_free(&summary);
    rate_limiter_destroy(limiter);
    pthread_mutex_destroy(&summary_lock);
    pthread_mutex_destroy(&print_lock);
    session_free(&sess_a);
    session_free(&sess_b);
    http_client_global_cleanup();
    config_free(&cfg);
    return 0;
}
