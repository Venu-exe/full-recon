CC = gcc
CFLAGS = -Wall -Wextra -O2 -Iinclude -Ilib -D_GNU_SOURCE
LDFLAGS = -lcurl -lpthread

SRC = src/main.c src/http_client.c src/json_diff.c src/reporter.c \
      src/thread_pool.c src/rate_limit.c src/header_analysis.c src/config.c \
      lib/cJSON.c
OBJ = $(SRC:.c=.o)
BIN = idor_prober

all: $(BIN)

$(BIN): $(OBJ)
	$(CC) $(OBJ) -o $(BIN) $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJ) $(BIN)

.PHONY: all clean
