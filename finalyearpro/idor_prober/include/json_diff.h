#ifndef JSON_DIFF_H
#define JSON_DIFF_H

typedef enum {
    VERDICT_DENIED,           /* B properly blocked from A's resource */
    VERDICT_IDOR_CONFIRMED,   /* B received A's actual data */
    VERDICT_SAFE_REMAPPED,    /* B got 200 but it's B's own data, not A's */
    VERDICT_AMBIGUOUS,        /* not JSON, or inconclusive - needs manual review */
    VERDICT_NOT_JSON
} verdict_t;

typedef struct {
    verdict_t verdict;
    double cross_similarity;      /* similarity of resp_A vs resp_B_cross, 0.0-1.0 */
    double shape_similarity;      /* structural (keys+types) similarity component */
    double value_similarity;      /* leaf-value similarity component */
    double baseline_similarity;   /* resp_B_cross vs resp_B_own, if baseline provided; -1 if unavailable */
    int confidence;               /* 0-100, human-facing score */
    char reason[512];             /* human-readable explanation for the report */
} diff_result_t;

/* Core classification entrypoint.
 * body_a          : A's own response body to the target resource
 * body_b_cross    : B's response body to the SAME url A used
 * body_b_own      : B's response to their own equivalent resource (NULL if not available)
 * status_b_cross  : HTTP status code B got on the cross-account request
 */
void classify_idor(const char *body_a,
                    const char *body_b_cross,
                    const char *body_b_own,
                    long status_b_cross,
                    diff_result_t *out);

#endif
