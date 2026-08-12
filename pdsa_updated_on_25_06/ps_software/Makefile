CC      ?= aarch64-linux-gnu-gcc
CFLAGS  ?= -O2 -Wall -Wextra -static
INCLUDES = -I. -I./mining

# pdsa_miner: standalone CSR test (old interface)
TARGET1    = pdsa_miner
SRCS1     = pdsa_miner.c pdsa_csr.c
OBJS1     = $(SRCS1:.c=.o)

# pdsa_main: full PDSA mining controller (main production binary)
TARGET2    = pdsa_main
SRCS2     = pdsa_main.c \
            mining/sha256_sw.c
OBJS2     = $(SRCS2:.c=.o)

all: $(TARGET1) $(TARGET2)

$(TARGET1): $(OBJS1)
	$(CC) $(CFLAGS) -o $@ $^ -lm

pdsa_miner.o: pdsa_miner.c pdsa_csr.h
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

pdsa_csr.o: pdsa_csr.c pdsa_csr.h
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

$(TARGET2): $(OBJS2)
	$(CC) $(CFLAGS) -o $@ $^ -lm

pdsa_main.o: pdsa_main.c pdsa_csr_map.h pdsa_hal.h
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

mining/sha256_sw.o: mining/sha256_sw.c mining/sha256_sw.h
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

clean:
	rm -f $(OBJS1) $(OBJS2) $(TARGET1) $(TARGET2)

.PHONY: all clean
