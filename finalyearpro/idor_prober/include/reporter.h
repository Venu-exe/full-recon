#ifndef REPORTER_H
#define REPORTER_H

#include <stdio.h>
#include "json_diff.h"
#include "header_analysis.h"

typedef struct {
    char url[2048];
    char baseline_url[2048];
    char method[8];
    long status_a;
    long status_b_cross;
    long status_b_own;
    double time_a;
    double time_b_cross;
    double time_b_own;
    size_t body_len_a;
    size_t body_len_b_cross;
    size_t body_len_b_own;
    int have_baseline;
    diff_result_t diff;
    header_analysis_t hdr;
    char body_a_preview[512];
    char body_b_cross_preview[512];
    char body_b_own_preview[512];
} scan_result_t;

typedef struct {
    scan_result_t *results;
    int count;
    int cap;
    int total_idor;
    int total_denied;
    int total_safe;
    int total_ambiguous;
    int total_not_json;
} scan_summary_t;

void summary_init(scan_summary_t *s);
void summary_add(scan_summary_t *s, const scan_result_t *r);
void summary_free(scan_summary_t *s);

/* Print a single result to the stream (text mode, used for real-time output) */
void report_print_result(FILE *out, const scan_result_t *r, int verbose, int use_color);

/* Print progress line to stderr */
void report_progress(int current, int total, int use_color);

/* Print final summary banner */
void report_print_summary(FILE *out, const scan_summary_t *s, int use_color);

/* Write full JSON report to file */
void report_write_json(FILE *out, const scan_summary_t *s);

/* Write full HTML report to file */
void report_write_html(FILE *out, const scan_summary_t *s);

#endif
