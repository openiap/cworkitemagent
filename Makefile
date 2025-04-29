TARGET          := workitem_client
SRCS            := main.c
OBJS            := $(SRCS:.c=.o)

# Detect OS & architecture
UNAME_S         := $(shell uname -s)
ARCH            := $(shell uname -m)

ifeq ($(UNAME_S),Darwin)
    OS_SUFFIX   := macos
else ifeq ($(UNAME_S),Linux)
    OS_SUFFIX   := linux
else ifeq ($(UNAME_S),Windows_NT)
    OS_SUFFIX   := windows
else
    $(error Unsupported OS: $(UNAME_S))
endif

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
ifeq ($(OS_SUFFIX),macos)
    LIB_EXT := dylib
else ifeq ($(OS_SUFFIX),windows)
    LIB_EXT := dll
else
    LIB_EXT := so
endif

LIB_BASE        := openiap-$(OS_SUFFIX)-$(ARCH_SUFFIX)
LIB_SO          := $(LIB_DIR)/lib$(LIB_BASE).$(LIB_EXT)
LIB_GENERIC_SO  := $(LIB_DIR)/libopeniap_clib.$(LIB_EXT)

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
	  https://github.com/openiap/rustapi/releases/download/$(OPENIAP_VERSION)/lib$(LIB_BASE).$(LIB_EXT)
	@chmod +x $@ || true

# Copy to generic name so linker and loader see libopeniap_clib.dylib
prepare_lib: $(LIB_SO)
	@echo "Copying to generic name for loader..."
	@cp $(LIB_SO) $(LIB_GENERIC_SO)
ifeq ($(OS_SUFFIX),macos)
	@install_name_tool -id @rpath/libopeniap_clib.dylib $(LIB_GENERIC_SO)
endif

$(TARGET): $(OBJS) prepare_lib
	$(CC) $(OBJS) -o $(TARGET) $(LDFLAGS) -lopeniap_clib
ifeq ($(OS_SUFFIX),macos)
	@if [ -f $(TARGET) ]; then \
		install_name_tool -add_rpath @executable_path/lib $(TARGET); \
	fi
else ifeq ($(OS_SUFFIX),linux)
	@if [ -f $(TARGET) ]; then \
		patchelf --set-rpath '$$ORIGIN/lib' $(TARGET); \
	fi
endif

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
