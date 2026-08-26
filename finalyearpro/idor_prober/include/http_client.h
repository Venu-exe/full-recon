#ifndef HTTP_CLIENT_H
#define HTTP_CLIENT_H

#include <stddef.h>

typedef enum {
    HTTP_GET,
    HTTP_POST,
    HTTP_PUT,
    HTTP_DELETE,
    HTTP_PATCH
} http_method_t;

typedef struct {
    long status_code;
    char *body;          /* heap-allocated, caller frees */
    size_t body_len;
    char *headers_raw;   /* heap-allocated, caller frees */
    double time_total;   /* seconds, useful for timing-based side channels later */
} http_response_t;

typedef struct {
    char *cookie_header;      /* full "Cookie: a=b; c=d" value, or NULL */
    char *auth_header;        /* full "Authorization: Bearer xxx" value, or NULL */
    char *extra_headers[8];   /* optional extra raw "Key: Value" lines, NULL-terminated */
    int extra_header_count;
} session_t;

/* Loads a session definition from a simple text file.
 * File format (one directive per line, '#' starts a comment):
 *   Cookie: name=value; name2=value2
 *   Authorization: Bearer <token>
 *   Header: X-Custom: value
 * Returns 0 on success, -1 on failure. Caller must free via session_free(). */
int session_load_from_file(const char *path, session_t *out);
void session_free(session_t *s);

/* Performs a GET request against url using the given session's auth material.
 * Returns 0 on success (response populated), -1 on transport-level failure. */
int http_fetch(const char *url, const session_t *session, http_response_t *out);

/* Extended fetch: supports arbitrary HTTP methods and request bodies.
 * method: HTTP_GET, HTTP_POST, HTTP_PUT, HTTP_DELETE, HTTP_PATCH
 * body: request body string (NULL for no body)
 * content_type: Content-Type header value (NULL defaults to application/json) */
int http_fetch_ex(const char *url, const session_t *session,
                  http_method_t method, const char *body,
                  const char *content_type, http_response_t *out);

/* Parse a method string ("GET", "POST", etc.) into enum. Returns -1 on unknown. */
int http_method_from_str(const char *str, http_method_t *out);

/* Return string name of method. */
const char *http_method_to_str(http_method_t m);

void http_response_free(http_response_t *r);

/* One-time global init/cleanup for libcurl. Call once at program start/end. */
int http_client_global_init(void);
void http_client_global_cleanup(void);

#endif

