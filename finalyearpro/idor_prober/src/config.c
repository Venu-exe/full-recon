#include "config.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <unistd.h>

void config_init(config_t *cfg) {
    memset(cfg, 0, sizeof(config_t));
    cfg->method = strdup("GET");
    cfg->threads = 4;
    cfg->rate_limit = 0.0;
    cfg->use_color = isatty(STDOUT_FILENO) ? 1 : 0;
    cfg->format = REPORT_TEXT;
}

static char *trim_whitespace(char *str) {
    char *end;
    while (isspace((unsigned char)*str)) str++;
    if (*str == 0) return str;
    end = str + strlen(str) - 1;
    while (end > str && isspace((unsigned char)*end)) end--;
    end[1] = '\0';
    return str;
}

int config_load_from_file(const char *path, config_t *cfg) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;

    char line[1024];
    while (fgets(line, sizeof(line), f)) {
        char *tline = trim_whitespace(line);
        if (tline[0] == '#' || tline[0] == '\0') continue;

        char *eq = strchr(tline, '=');
        if (!eq) continue;

        *eq = '\0';
        char *key = trim_whitespace(tline);
        char *val = trim_whitespace(eq + 1);

        if (strcmp(key, "session_a") == 0) {
            if (cfg->session_a_path) free(cfg->session_a_path);
            cfg->session_a_path = strdup(val);
        } else if (strcmp(key, "session_b") == 0) {
            if (cfg->session_b_path) free(cfg->session_b_path);
            cfg->session_b_path = strdup(val);
        } else if (strcmp(key, "url") == 0) {
            if (cfg->single_url) free(cfg->single_url);
            cfg->single_url = strdup(val);
        } else if (strcmp(key, "baseline_url") == 0) {
            if (cfg->baseline_url) free(cfg->baseline_url);
            cfg->baseline_url = strdup(val);
        } else if (strcmp(key, "url_list") == 0) {
            if (cfg->list_path) free(cfg->list_path);
            cfg->list_path = strdup(val);
        } else if (strcmp(key, "baseline_list") == 0) {
            if (cfg->baseline_list_path) free(cfg->baseline_list_path);
            cfg->baseline_list_path = strdup(val);
        } else if (strcmp(key, "output") == 0) {
            if (cfg->out_path) free(cfg->out_path);
            cfg->out_path = strdup(val);
        } else if (strcmp(key, "method") == 0) {
            if (cfg->method) free(cfg->method);
            cfg->method = strdup(val);
        } else if (strcmp(key, "body") == 0) {
            if (cfg->body) free(cfg->body);
            cfg->body = strdup(val);
        } else if (strcmp(key, "content_type") == 0) {
            if (cfg->content_type) free(cfg->content_type);
            cfg->content_type = strdup(val);
        } else if (strcmp(key, "enum_range") == 0) {
            if (cfg->enum_range) free(cfg->enum_range);
            cfg->enum_range = strdup(val);
        } else if (strcmp(key, "verbose") == 0) {
            cfg->verbose = (strcmp(val, "1") == 0 || strcasecmp(val, "yes") == 0 || strcasecmp(val, "true") == 0) ? 1 : 0;
        } else if (strcmp(key, "threads") == 0) {
            cfg->threads = atoi(val);
        } else if (strcmp(key, "rate_limit") == 0) {
            cfg->rate_limit = atof(val);
        } else if (strcmp(key, "color") == 0) {
            if (strcasecmp(val, "auto") == 0) cfg->use_color = isatty(STDOUT_FILENO) ? 1 : 0;
            else cfg->use_color = (strcmp(val, "1") == 0 || strcasecmp(val, "yes") == 0 || strcasecmp(val, "true") == 0) ? 1 : 0;
        } else if (strcmp(key, "format") == 0) {
            if (strcasecmp(val, "json") == 0) cfg->format = REPORT_JSON;
            else if (strcasecmp(val, "html") == 0) cfg->format = REPORT_HTML;
            else cfg->format = REPORT_TEXT;
        }
    }
    fclose(f);
    return 0;
}

void config_free(config_t *cfg) {
    if (cfg->session_a_path) free(cfg->session_a_path);
    if (cfg->session_b_path) free(cfg->session_b_path);
    if (cfg->single_url) free(cfg->single_url);
    if (cfg->baseline_url) free(cfg->baseline_url);
    if (cfg->list_path) free(cfg->list_path);
    if (cfg->baseline_list_path) free(cfg->baseline_list_path);
    if (cfg->out_path) free(cfg->out_path);
    if (cfg->method) free(cfg->method);
    if (cfg->body) free(cfg->body);
    if (cfg->content_type) free(cfg->content_type);
    if (cfg->enum_range) free(cfg->enum_range);
    memset(cfg, 0, sizeof(config_t));
}
