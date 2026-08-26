#ifndef THREAD_POOL_H
#define THREAD_POOL_H

#include <pthread.h>

typedef void (*task_func_t)(void *arg);

typedef struct {
    task_func_t func;
    void *arg;
} task_t;

typedef struct {
    pthread_t *threads;
    task_t *queue;
    int queue_size;
    int queue_cap;
    int head;
    int tail;
    int thread_count;
    int shutdown;
    int active_tasks;  /* number of tasks currently being executed */
    pthread_mutex_t lock;
    pthread_cond_t notify;      /* signals workers that a new task is available */
    pthread_cond_t all_done;    /* signals waiter that all tasks are complete */
} thread_pool_t;

thread_pool_t *thread_pool_create(int num_threads);
int thread_pool_submit(thread_pool_t *pool, task_func_t func, void *arg);
void thread_pool_wait(thread_pool_t *pool);   /* block until all queued tasks finish */
void thread_pool_destroy(thread_pool_t *pool);

#endif
