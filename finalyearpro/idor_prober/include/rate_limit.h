#ifndef RATE_LIMIT_H
#define RATE_LIMIT_H

#include <pthread.h>
#include <time.h>

typedef struct {
    double interval_ns;     /* minimum nanoseconds between requests */
    struct timespec last;   /* timestamp of last permitted request */
    pthread_mutex_t lock;
} rate_limiter_t;

/* Pass 0 or negative to disable limiting. */
rate_limiter_t *rate_limiter_create(double requests_per_second);

/* Thread-safe: blocks the calling thread until the next request is permitted. */
void rate_limiter_wait(rate_limiter_t *rl);

void rate_limiter_destroy(rate_limiter_t *rl);

#endif
