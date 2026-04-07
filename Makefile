CC = sysasm
LDFLAGS =

SRC_DIR = src
SRC = $(SRC_DIR)/main.hasm

BIN = sysdos.bin

.PHONY: all clean run

all:
	$(CC) $(SRC) -o $(BIN) $(LDFLAGS)

clean:
	@rm -f $(BIN)

verbose: LDFLAGS = -V
verbose: all

run:
	@./sysvm $(BIN)