#include "rate_limit.h"
#include <stdlib.h>
#include <time.h>

rate_limiter_t *rate_limiter_create(double requests_per_second) {
    if (requests_per_second <= 0) {
        return NULL;
    }
    
    rate_limiter_t *rl = (rate_limiter_t *)malloc(sizeof(rate_limiter_t));
    if (rl == NULL) {
        return NULL;
    }
    
    rl->interval_ns = 1e9 / requests_per_second;
    if (pthread_mutex_init(&(rl->lock), NULL) != 0) {
        free(rl);
        return NULL;
    }
    
    clock_gettime(CLOCK_MONOTONIC, &(rl->last));
    
    return rl;
}

void rate_limiter_wait(rate_limiter_t *rl) {
    if (rl == NULL) {
        return;
    }
    
    pthread_mutex_lock(&(rl->lock));
    
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    
    long long last_ns = (long long)rl->last.tv_sec * 1000000000LL + rl->last.tv_nsec;
    long long now_ns = (long long)now.tv_sec * 1000000000LL + now.tv_nsec;
    long long next_allowed_ns = last_ns + (long long)rl->interval_ns;
    
    if (now_ns < next_allowed_ns) {
        long long diff_ns = next_allowed_ns - now_ns;
        struct timespec delay;
        delay.tv_sec = diff_ns / 1000000000LL;
        delay.tv_nsec = diff_ns % 1000000000LL;
        nanosleep(&delay, NULL);
        
        clock_gettime(CLOCK_MONOTONIC, &(rl->last));
    } else {
        rl->last = now;
    }
    
    pthread_mutex_unlock(&(rl->lock));
}

void rate_limiter_destroy(rate_limiter_t *rl) {
    if (rl == NULL) {
        return;
    }
    
    pthread_mutex_destroy(&(rl->lock));
    free(rl);
}
