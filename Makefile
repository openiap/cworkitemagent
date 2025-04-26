TARGET          := workitem_client
SRCS            := main.c
OBJS            := $(SRCS:.c=.o)

# Detect OS & architecture
UNAME_S         := $(shell uname -s)
ARCH            := $(shell uname -m)
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

# Compiler settings
CC              := gcc
CFLAGS          := -I. -Wall -Wextra -O2

# OpenIAP version and header URL
OPENIAP_VERSION := 0.0.34
HEADER_URL      := https://raw.githubusercontent.com/openiap/rustapi/8e0a37ff19ed2d61f8130b6b85bc53d613f84f20/crates/clib/clib_openiap.h

# Library output directory
LIB_DIR         := lib

# Dynamic linking flags
LDFLAGS         := -L$(LIB_DIR) -Wl,-rpath,'$$ORIGIN/$(LIB_DIR)'

# Library names
LIB_BASE        := openiap-linux-$(ARCH_SUFFIX)
LIB_SO          := $(LIB_DIR)/lib$(LIB_BASE).so
LIB_GENERIC_SO  := $(LIB_DIR)/libopeniap_clib.so

# Phony targets
.PHONY: all clean download_deps prepare_lib dockerbuild run

# Default build: dynamic
all: download_deps prepare_lib $(TARGET)
	@echo "Built $(TARGET) (dynamic)"

# Download header + dynamic library
download_deps: clib_openiap.h $(LIB_SO)

clib_openiap.h:
	@echo "Downloading C header..."
	@curl -sSL -o $@ $(HEADER_URL)

$(LIB_DIR):
	@mkdir -p $(LIB_DIR)

$(LIB_SO): | $(LIB_DIR)
	@echo "Downloading OpenIAP shared library..."
	@curl -sSL -o $@ \
	  https://github.com/openiap/rustapi/releases/download/$(OPENIAP_VERSION)/lib$(LIB_BASE).so
	@chmod +x $@ || true

# Copy to generic name so linker and loader see libopeniap_clib.so
prepare_lib: $(LIB_SO)
	@echo "Copying to generic name for loader..."
	@cp $(LIB_SO) $(LIB_GENERIC_SO)

# Compile & link dynamically
$(TARGET): $(OBJS)
	$(CC) $(OBJS) -o $(TARGET) $(LDFLAGS) -lopeniap_clib

%.o: %.c clib_openiap.h
	$(CC) $(CFLAGS) -c $< -o $@

# Patch the interpreter on a NixOS-built binary
dockerbuild: all
	@command -v patchelf >/dev/null 2>&1 || { \
	  echo "Error: patchelf is required for dockerbuild. Install it locally."; \
	  exit 1; }
	@patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 $(TARGET)
	@echo "✓ $(TARGET) patched for native loader"

clean:
	@rm -f $(TARGET) $(OBJS) clib_openiap.h
	@rm -rf $(LIB_DIR)

run: $(TARGET)
	@./$(TARGET)
