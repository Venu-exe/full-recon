#include "thread_pool.h"
#include <stdlib.h>
#include <stdio.h>

static void *thread_worker(void *arg) {
    thread_pool_t *pool = (thread_pool_t *)arg;
    
    while (1) {
        pthread_mutex_lock(&(pool->lock));
        
        while ((pool->queue_size == 0) && (!pool->shutdown)) {
            pthread_cond_wait(&(pool->notify), &(pool->lock));
        }
        
        if (pool->shutdown && pool->queue_size == 0) {
            pthread_mutex_unlock(&(pool->lock));
            pthread_exit(NULL);
        }
        
        task_t task;
        task.func = pool->queue[pool->head].func;
        task.arg = pool->queue[pool->head].arg;
        
        pool->head = (pool->head + 1) % pool->queue_cap;
        pool->queue_size--;
        pool->active_tasks++;
        
        pthread_mutex_unlock(&(pool->lock));
        
        (*(task.func))(task.arg);
        
        pthread_mutex_lock(&(pool->lock));
        pool->active_tasks--;
        if (pool->queue_size == 0 && pool->active_tasks == 0) {
            pthread_cond_signal(&(pool->all_done));
        }
        pthread_mutex_unlock(&(pool->lock));
    }
    return NULL;
}

thread_pool_t *thread_pool_create(int num_threads) {
    if (num_threads <= 0) return NULL;
    
    thread_pool_t *pool = (thread_pool_t *)malloc(sizeof(thread_pool_t));
    if (pool == NULL) return NULL;
    
    pool->thread_count = num_threads;
    pool->shutdown = 0;
    pool->active_tasks = 0;
    
    pool->queue_cap = 256;
    pool->queue_size = 0;
    pool->head = 0;
    pool->tail = 0;
    pool->queue = (task_t *)malloc(sizeof(task_t) * pool->queue_cap);
    if (pool->queue == NULL) {
        free(pool);
        return NULL;
    }
    
    if (pthread_mutex_init(&(pool->lock), NULL) != 0 ||
        pthread_cond_init(&(pool->notify), NULL) != 0 ||
        pthread_cond_init(&(pool->all_done), NULL) != 0) {
        free(pool->queue);
        free(pool);
        return NULL;
    }
    
    pool->threads = (pthread_t *)malloc(sizeof(pthread_t) * num_threads);
    if (pool->threads == NULL) {
        pthread_mutex_destroy(&(pool->lock));
        pthread_cond_destroy(&(pool->notify));
        pthread_cond_destroy(&(pool->all_done));
        free(pool->queue);
        free(pool);
        return NULL;
    }
    
    for (int i = 0; i < num_threads; i++) {
        if (pthread_create(&(pool->threads[i]), NULL, thread_worker, (void *)pool) != 0) {
            thread_pool_destroy(pool);
            return NULL;
        }
    }
    
    return pool;
}

int thread_pool_submit(thread_pool_t *pool, task_func_t func, void *arg) {
    if (pool == NULL || func == NULL) return -1;
    
    pthread_mutex_lock(&(pool->lock));
    
    if (pool->shutdown) {
        pthread_mutex_unlock(&(pool->lock));
        return -1;
    }
    
    if (pool->queue_size == pool->queue_cap) {
        int new_cap = pool->queue_cap * 2;
        task_t *new_queue = (task_t *)malloc(sizeof(task_t) * new_cap);
        if (new_queue == NULL) {
            pthread_mutex_unlock(&(pool->lock));
            return -1;
        }
        for (int i = 0; i < pool->queue_size; i++) {
            new_queue[i] = pool->queue[(pool->head + i) % pool->queue_cap];
        }
        free(pool->queue);
        pool->queue = new_queue;
        pool->head = 0;
        pool->tail = pool->queue_size;
        pool->queue_cap = new_cap;
    }
    
    pool->queue[pool->tail].func = func;
    pool->queue[pool->tail].arg = arg;
    pool->tail = (pool->tail + 1) % pool->queue_cap;
    pool->queue_size++;
    
    pthread_cond_signal(&(pool->notify));
    pthread_mutex_unlock(&(pool->lock));
    
    return 0;
}

void thread_pool_wait(thread_pool_t *pool) {
    if (pool == NULL) return;
    
    pthread_mutex_lock(&(pool->lock));
    while (pool->queue_size > 0 || pool->active_tasks > 0) {
        pthread_cond_wait(&(pool->all_done), &(pool->lock));
    }
    pthread_mutex_unlock(&(pool->lock));
}

void thread_pool_destroy(thread_pool_t *pool) {
    if (pool == NULL) return;
    
    pthread_mutex_lock(&(pool->lock));
    pool->shutdown = 1;
    pthread_cond_broadcast(&(pool->notify));
    pthread_mutex_unlock(&(pool->lock));
    
    for (int i = 0; i < pool->thread_count; i++) {
        pthread_join(pool->threads[i], NULL);
    }
    
    pthread_mutex_destroy(&(pool->lock));
    pthread_cond_destroy(&(pool->notify));
    pthread_cond_destroy(&(pool->all_done));
    
    free(pool->threads);
    free(pool->queue);
    free(pool);
}
