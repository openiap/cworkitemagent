# Detect the operating system.
UNAME_S := $(shell uname -s)
# Detect architecture
ARCH := $(shell uname -m)
ifeq ($(ARCH),x86_64)
    ARCH_SUFFIX := x64
else ifeq ($(ARCH),amd64)
    ARCH_SUFFIX := x64
else ifeq ($(ARCH),arm64)
    ARCH_SUFFIX := arm64
else ifeq ($(ARCH),aarch64)
    ARCH_SUFFIX := arm64
else ifeq ($(ARCH),i686)
    ARCH_SUFFIX := i686
else ifeq ($(ARCH),i386)
    ARCH_SUFFIX := i686
else
    $(error Unsupported architecture: $(ARCH))
endif

# Set the C compiler.
CC := gcc

# Determine build type.
ifdef DEBUG
    BUILD_TYPE := debug
    LIB_DIR := ../target/debug
    CFLAGS := -I. -Wall -Wextra -g -O0
else
    BUILD_TYPE := release
    LIB_DIR := lib
    CFLAGS := -I. -Wall -Wextra -O2
endif

# OpenIAP version
OPENIAP_VERSION := 0.0.28
# Header file URL
HEADER_URL := https://raw.githubusercontent.com/openiap/rustapi/ba787072946f96d29b8f5eb01abf8dc06afa8603/crates/clib/clib_openiap.h

# Set linker flags to use the appropriate lib directory with rpath.
LDFLAGS := -L$(LIB_DIR) -Wl,-rpath,'$$ORIGIN/$(LIB_DIR)'

# Choose the library name based on OS, architecture, and build type.
ifeq ($(BUILD_TYPE),debug)
    # Debug build uses the common library name across platforms.
    LIB_NAME := openiap_clib
else
    ifeq ($(UNAME_S),Linux)
        LIB_NAME := openiap-linux-$(ARCH_SUFFIX)
        LIB_URL := https://github.com/openiap/rustapi/releases/download/$(OPENIAP_VERSION)/libopeniap-linux-$(ARCH_SUFFIX).so
    else ifeq ($(UNAME_S),Darwin)
        LIB_NAME := openiap-macos-$(ARCH_SUFFIX)
        LIB_URL := https://github.com/openiap/rustapi/releases/download/$(OPENIAP_VERSION)/libopeniap-macos-$(ARCH_SUFFIX).dylib
    else ifeq ($(UNAME_S),Windows_NT)
        LIB_NAME := openiap-windows-$(ARCH_SUFFIX)
        LIB_URL := https://github.com/openiap/rustapi/releases/download/$(OPENIAP_VERSION)/openiap-windows-$(ARCH_SUFFIX).dll
    else
        $(error Unsupported OS: $(UNAME_S))
    endif
endif

# Use the actual library file path to avoid -l prefix issues
ifeq ($(UNAME_S),Linux)
    LIB := $(LIB_DIR)/lib$(LIB_NAME).so
else ifeq ($(UNAME_S),Darwin)
    LIB := $(LIB_DIR)/lib$(LIB_NAME).dylib
else ifeq ($(UNAME_S),Windows_NT)
    LIB := $(LIB_DIR)/$(LIB_NAME).dll
endif

# Binary name and source files.
TARGET  := workitem_client
SRCS    := main.c
OBJS    := $(SRCS:.c=.o)

# Add symlink target
.PHONY: all clean run debug symlink download_deps

all: download_deps symlink $(TARGET)
	@echo "Built $(TARGET) in $(BUILD_TYPE) mode."

# Download dependencies (header and library files)
download_deps: clib_openiap.h $(LIB_DIR) $(LIB)

clib_openiap.h:
	@echo "Downloading header file..."
	@if command -v curl >/dev/null 2>&1; then \
		curl -s -L -o clib_openiap.h $(HEADER_URL); \
	elif command -v wget >/dev/null 2>&1; then \
		wget -q -O clib_openiap.h $(HEADER_URL); \
	else \
		echo "Error: Neither curl nor wget is available. Please install one of them."; \
		exit 1; \
	fi

$(LIB_DIR):
	@echo "Creating library directory..."
	@mkdir -p $(LIB_DIR)

$(LIB):
	@echo "Downloading library file..."
	@if command -v curl >/dev/null 2>&1; then \
		curl -s -L -o $(LIB) $(LIB_URL); \
	elif command -v wget >/dev/null 2>&1; then \
		wget -q -O $(LIB) $(LIB_URL); \
	else \
		echo "Error: Neither curl nor wget is available. Please install one of them."; \
		exit 1; \
	fi
	@chmod +x $(LIB)

# Create necessary symlink for runtime library loading
symlink:
ifeq ($(UNAME_S),Linux)
	@if [ ! -L "$(LIB_DIR)/libopeniap_clib.so" ]; then \
		echo "Creating symlink for runtime library loading"; \
		ln -sf lib$(LIB_NAME).so $(LIB_DIR)/libopeniap_clib.so; \
	fi
else ifeq ($(UNAME_S),Darwin)
	@if [ ! -L "$(LIB_DIR)/libopeniap_clib.dylib" ]; then \
		echo "Creating symlink for runtime library loading"; \
		ln -sf lib$(LIB_NAME).dylib $(LIB_DIR)/libopeniap_clib.dylib; \
	fi
endif

$(TARGET): $(OBJS)
	$(CC) $(OBJS) -o $(TARGET) $(LDFLAGS) $(LIB)

%.o: %.c clib_openiap.h
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(TARGET) $(OBJS)
	rm -f $(LIB_DIR)/libopeniap_clib.so $(LIB_DIR)/libopeniap_clib.dylib

run: $(TARGET)
	./$(TARGET)

debug:
	$(MAKE) DEBUG=1 all
