#include "json_diff.h"
#include "cJSON.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------- internal field list: (path, type) pairs for shape fingerprinting ---------- */

typedef struct {
    char *path;
    char type;   /* 'n' null, 'b' bool, 'd' number, 's' string, 'a' array, 'o' object */
    char *value; /* stringified leaf value, only meaningful for n/b/d/s */
} field_t;

typedef struct {
    field_t *items;
    int count;
    int cap;
} field_list_t;

static void fl_init(field_list_t *l) { l->items = NULL; l->count = 0; l->cap = 0; }

static void fl_add(field_list_t *l, const char *path, char type, const char *value) {
    if (l->count >= l->cap) {
        l->cap = l->cap ? l->cap * 2 : 16;
        l->items = realloc(l->items, l->cap * sizeof(field_t));
    }
    l->items[l->count].path = strdup(path);
    l->items[l->count].type = type;
    l->items[l->count].value = value ? strdup(value) : NULL;
    l->count++;
}

static void fl_free(field_list_t *l) {
    for (int i = 0; i < l->count; i++) {
        free(l->items[i].path);
        free(l->items[i].value);
    }
    free(l->items);
}

static void leaf_value_str(cJSON *node, char *buf, size_t buflen) {
    if (cJSON_IsNull(node)) snprintf(buf, buflen, "null");
    else if (cJSON_IsBool(node)) snprintf(buf, buflen, "%s", cJSON_IsTrue(node) ? "true" : "false");
    else if (cJSON_IsNumber(node)) snprintf(buf, buflen, "%g", node->valuedouble);
    else if (cJSON_IsString(node)) snprintf(buf, buflen, "%s", node->valuestring);
    else buf[0] = '\0';
}

/* Recursively walk a JSON node, recording a (path,type[,value]) entry for every
 * field encountered. Arrays are represented by their first element under path[]
 * -- this is a heuristic simplification appropriate for typical REST payloads. */
static void walk_shape(cJSON *node, const char *prefix, field_list_t *list) {
    if (!node) return;

    if (cJSON_IsObject(node)) {
        cJSON *child = node->child;
        while (child) {
            char path[1024];
            if (prefix[0]) snprintf(path, sizeof(path), "%s.%s", prefix, child->string);
            else snprintf(path, sizeof(path), "%s", child->string);
            walk_shape(child, path, list);
            child = child->next;
        }
    } else if (cJSON_IsArray(node)) {
        char path[1024];
        snprintf(path, sizeof(path), "%s[]", prefix);
        fl_add(list, path, 'a', NULL);
        cJSON *first = node->child;
        if (first) walk_shape(first, path, list);
    } else {
        char valbuf[512];
        leaf_value_str(node, valbuf, sizeof(valbuf));
        char type = cJSON_IsNull(node) ? 'n' :
                    cJSON_IsBool(node) ? 'b' :
                    cJSON_IsNumber(node) ? 'd' :
                    cJSON_IsString(node) ? 's' : '?';
        fl_add(list, prefix, type, valbuf);
    }
}

/* Structural similarity: Jaccard index over (path,type) pairs. */
static double shape_similarity(field_list_t *a, field_list_t *b) {
    if (a->count == 0 && b->count == 0) return 1.0;
    if (a->count == 0 || b->count == 0) return 0.0;

    int matches = 0;
    for (int i = 0; i < a->count; i++) {
        for (int j = 0; j < b->count; j++) {
            if (a->items[i].type == b->items[j].type &&
                strcmp(a->items[i].path, b->items[j].path) == 0) {
                matches++;
                break;
            }
        }
    }
    int union_count = a->count + b->count - matches;
    return union_count > 0 ? (double)matches / (double)union_count : 1.0;
}

/* Value similarity: of the paths common to both lists, what fraction have
 * identical leaf values? This is what actually distinguishes "same shape,
 * different person's data" from "literally the same data came back". */
static double value_similarity(field_list_t *a, field_list_t *b) {
    int common = 0, matched = 0;
    for (int i = 0; i < a->count; i++) {
        if (a->items[i].type == 'a' || a->items[i].type == 'o') continue; /* containers, not leaves */
        for (int j = 0; j < b->count; j++) {
            if (strcmp(a->items[i].path, b->items[j].path) == 0 && a->items[i].type == b->items[j].type) {
                common++;
                if (a->items[i].value && b->items[j].value &&
                    strcmp(a->items[i].value, b->items[j].value) == 0) {
                    matched++;
                }
                break;
            }
        }
    }
    if (common == 0) return 0.0;
    return (double)matched / (double)common;
}

static double combined_similarity(double shape, double value) {
    /* Value overlap matters more: identical shape with totally different
     * values is the classic "still IDOR, just different person" case. */
    return shape * 0.35 + value * 0.65;
}

void classify_idor(const char *body_a,
                    const char *body_b_cross,
                    const char *body_b_own,
                    long status_b_cross,
                    diff_result_t *out) {
    memset(out, 0, sizeof(*out));
    out->baseline_similarity = -1.0;

    /* Fast path: an explicit access-denial status code is a denial regardless
     * of body content. */
    if (status_b_cross == 401 || status_b_cross == 403) {
        out->verdict = VERDICT_DENIED;
        out->confidence = 90;
        snprintf(out->reason, sizeof(out->reason),
                 "HTTP %ld returned for cross-account request -- access control rejected the request at the transport layer.",
                 status_b_cross);
        return;
    }

    cJSON *json_a = cJSON_Parse(body_a);
    cJSON *json_b_cross = cJSON_Parse(body_b_cross);

    if (!json_a || !json_b_cross) {
        /* Not JSON (HTML error page, plaintext, etc). Fall back to a crude
         * but honest raw comparison so the tool still produces a signal. */
        if (json_a) cJSON_Delete(json_a);
        if (json_b_cross) cJSON_Delete(json_b_cross);

        if (strlen(body_b_cross) > 20 && strcmp(body_a, body_b_cross) == 0) {
            out->verdict = VERDICT_IDOR_CONFIRMED;
            out->cross_similarity = 1.0;
            out->confidence = 70;
            snprintf(out->reason, sizeof(out->reason),
                     "Non-JSON response body is byte-for-byte identical between the two accounts.");
        } else {
            out->verdict = VERDICT_NOT_JSON;
            out->confidence = 0;
            snprintf(out->reason, sizeof(out->reason),
                     "Response is not valid JSON; structural diffing unavailable. Manual review required.");
        }
        return;
    }

    field_list_t fl_a, fl_b_cross;
    fl_init(&fl_a);
    fl_init(&fl_b_cross);
    walk_shape(json_a, "", &fl_a);
    walk_shape(json_b_cross, "", &fl_b_cross);

    double shape_sim = shape_similarity(&fl_a, &fl_b_cross);
    double value_sim = value_similarity(&fl_a, &fl_b_cross);
    double cross_sim = combined_similarity(shape_sim, value_sim);

    out->shape_similarity = shape_sim;
    out->value_similarity = value_sim;
    out->cross_similarity = cross_sim;

    double baseline_sim = -1.0;
    if (body_b_own) {
        cJSON *json_b_own = cJSON_Parse(body_b_own);
        if (json_b_own) {
            field_list_t fl_b_own;
            fl_init(&fl_b_own);
            walk_shape(json_b_own, "", &fl_b_own);
            double bs_shape = shape_similarity(&fl_b_cross, &fl_b_own);
            double bs_value = value_similarity(&fl_b_cross, &fl_b_own);
            baseline_sim = combined_similarity(bs_shape, bs_value);
            fl_free(&fl_b_own);
            cJSON_Delete(json_b_own);
        }
    }
    out->baseline_similarity = baseline_sim;

    /* --- decision logic --- */
    if (cross_sim >= 0.75 && (baseline_sim < 0 || baseline_sim < 0.4)) {
        out->verdict = VERDICT_IDOR_CONFIRMED;
        out->confidence = (int)(cross_sim * 100);
        snprintf(out->reason, sizeof(out->reason),
                 "B's response to A's resource matches A's data (shape=%.2f, value=%.2f) and does not match B's own baseline%s.",
                 shape_sim, value_sim, baseline_sim < 0 ? " (baseline not tested)" : "");
    } else if (cross_sim >= 0.75 && baseline_sim >= 0.75) {
        out->verdict = VERDICT_AMBIGUOUS;
        out->confidence = 40;
        snprintf(out->reason, sizeof(out->reason),
                 "B's response matches both A's data and B's own baseline (sim=%.2f) -- endpoint may return generic/shared data. Manual review recommended.",
                 baseline_sim);
    } else if (cross_sim < 0.4 && baseline_sim >= 0.6) {
        out->verdict = VERDICT_SAFE_REMAPPED;
        out->confidence = (int)(baseline_sim * 100);
        snprintf(out->reason, sizeof(out->reason),
                 "B's response to A's URL matches B's own baseline (sim=%.2f), not A's data -- access appears correctly scoped server-side.",
                 baseline_sim);
    } else if (status_b_cross >= 200 && status_b_cross < 300 && cross_sim < 0.4) {
        out->verdict = VERDICT_AMBIGUOUS;
        out->confidence = 30;
        snprintf(out->reason, sizeof(out->reason),
                 "HTTP 200 but low similarity to A's data (%.2f) and no baseline to compare against. Could be safe or could be a differently-shaped leak -- inspect manually.",
                 cross_sim);
    } else {
        out->verdict = VERDICT_AMBIGUOUS;
        out->confidence = 25;
        snprintf(out->reason, sizeof(out->reason),
                 "Inconclusive signal (cross_sim=%.2f, baseline_sim=%.2f). Recommend manual inspection.",
                 cross_sim, baseline_sim);
    }

    fl_free(&fl_a);
    fl_free(&fl_b_cross);
    cJSON_Delete(json_a);
    cJSON_Delete(json_b_cross);
}
