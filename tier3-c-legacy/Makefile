CC=gcc
CFLAGS=-Wall -O2
TARGET=loan-risk-server
SRC=src/server.c
INSTALL_DIR=/opt/loan-risk-engine

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC)

clean:
	rm -f $(TARGET)

install: $(TARGET)
	mkdir -p $(INSTALL_DIR)
	mkdir -p /var/log/loan-risk-engine
	cp $(TARGET) $(INSTALL_DIR)/
	chmod +x $(INSTALL_DIR)/$(TARGET)
	@echo "Installation complete. Binary installed to $(INSTALL_DIR)/$(TARGET)"

.PHONY: all clean install
