#include "http_client.h"
#include <curl/curl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char *data;
    size_t len;
} membuf_t;

static size_t write_cb(void *contents, size_t size, size_t nmemb, void *userp) {
    size_t realsize = size * nmemb;
    membuf_t *mem = (membuf_t *)userp;
    char *ptr = realloc(mem->data, mem->len + realsize + 1);
    if (!ptr) return 0; /* signals error to curl */
    mem->data = ptr;
    memcpy(&(mem->data[mem->len]), contents, realsize);
    mem->len += realsize;
    mem->data[mem->len] = '\0';
    return realsize;
}

int http_client_global_init(void) {
    return curl_global_init(CURL_GLOBAL_DEFAULT) == CURLE_OK ? 0 : -1;
}

void http_client_global_cleanup(void) {
    curl_global_cleanup();
}

static char *trim(char *s) {
    while (*s == ' ' || *s == '\t') s++;
    char *end = s + strlen(s) - 1;
    while (end > s && (*end == '\n' || *end == '\r' || *end == ' ' || *end == '\t')) {
        *end = '\0';
        end--;
    }
    return s;
}

int session_load_from_file(const char *path, session_t *out) {
    memset(out, 0, sizeof(*out));
    FILE *f = fopen(path, "r");
    if (!f) {
        fprintf(stderr, "[!] Could not open session file: %s\n", path);
        return -1;
    }

    char line[4096];
    while (fgets(line, sizeof(line), f)) {
        char *l = trim(line);
        if (l[0] == '\0' || l[0] == '#') continue;

        if (strncasecmp(l, "Cookie:", 7) == 0) {
            char *val = trim(l + 7);
            char buf[4200];
            snprintf(buf, sizeof(buf), "Cookie: %s", val);
            out->cookie_header = strdup(buf);
        } else if (strncasecmp(l, "Authorization:", 14) == 0) {
            char *val = trim(l + 14);
            char buf[4200];
            snprintf(buf, sizeof(buf), "Authorization: %s", val);
            out->auth_header = strdup(buf);
        } else if (strncasecmp(l, "Header:", 7) == 0) {
            if (out->extra_header_count < 8) {
                out->extra_headers[out->extra_header_count++] = strdup(trim(l + 7));
            }
        }
    }
    fclose(f);
    return 0;
}

void session_free(session_t *s) {
    if (!s) return;
    free(s->cookie_header);
    free(s->auth_header);
    for (int i = 0; i < s->extra_header_count; i++) free(s->extra_headers[i]);
}

int http_fetch(const char *url, const session_t *session, http_response_t *out) {
    return http_fetch_ex(url, session, HTTP_GET, NULL, NULL, out);
}

int http_fetch_ex(const char *url, const session_t *session,
                  http_method_t method, const char *body,
                  const char *content_type, http_response_t *out) {
    memset(out, 0, sizeof(*out));
    CURL *curl = curl_easy_init();
    if (!curl) return -1;

    membuf_t body_buf = {0};
    membuf_t hdr_buf = {0};

    struct curl_slist *headers = NULL;
    if (session) {
        if (session->cookie_header) headers = curl_slist_append(headers, session->cookie_header);
        if (session->auth_header) headers = curl_slist_append(headers, session->auth_header);
        for (int i = 0; i < session->extra_header_count; i++) {
            headers = curl_slist_append(headers, session->extra_headers[i]);
        }
    }

    /* Set HTTP method */
    switch (method) {
        case HTTP_POST:
            curl_easy_setopt(curl, CURLOPT_POST, 1L);
            break;
        case HTTP_PUT:
            curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "PUT");
            break;
        case HTTP_DELETE:
            curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "DELETE");
            break;
        case HTTP_PATCH:
            curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "PATCH");
            break;
        case HTTP_GET:
        default:
            /* GET is the default */
            break;
    }

    /* Set request body if provided */
    if (body && body[0]) {
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body);
        char ct_header[256];
        snprintf(ct_header, sizeof(ct_header), "Content-Type: %s",
                 content_type ? content_type : "application/json");
        headers = curl_slist_append(headers, ct_header);
    }

    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &body_buf);
    curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_HEADERDATA, &hdr_buf);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 5L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 20L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "idor-prober/2.0 (authorized-testing)");

    CURLcode res = curl_easy_perform(curl);
    if (res != CURLE_OK) {
        fprintf(stderr, "[!] Request failed for %s: %s\n", url, curl_easy_strerror(res));
        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);
        free(body_buf.data);
        free(hdr_buf.data);
        return -1;
    }

    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &out->status_code);
    curl_easy_getinfo(curl, CURLINFO_TOTAL_TIME, &out->time_total);

    out->body = body_buf.data ? body_buf.data : strdup("");
    out->body_len = body_buf.len;
    out->headers_raw = hdr_buf.data ? hdr_buf.data : strdup("");

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return 0;
}

int http_method_from_str(const char *str, http_method_t *out) {
    if (!str) return -1;
    if (strcasecmp(str, "GET") == 0) { *out = HTTP_GET; return 0; }
    if (strcasecmp(str, "POST") == 0) { *out = HTTP_POST; return 0; }
    if (strcasecmp(str, "PUT") == 0) { *out = HTTP_PUT; return 0; }
    if (strcasecmp(str, "DELETE") == 0) { *out = HTTP_DELETE; return 0; }
    if (strcasecmp(str, "PATCH") == 0) { *out = HTTP_PATCH; return 0; }
    return -1;
}

const char *http_method_to_str(http_method_t m) {
    switch (m) {
        case HTTP_GET:    return "GET";
        case HTTP_POST:   return "POST";
        case HTTP_PUT:    return "PUT";
        case HTTP_DELETE: return "DELETE";
        case HTTP_PATCH:  return "PATCH";
    }
    return "GET";
}

void http_response_free(http_response_t *r) {
    if (!r) return;
    free(r->body);
    free(r->headers_raw);
}
