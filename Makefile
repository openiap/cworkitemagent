# Detect the operating system.
UNAME_S := $(shell uname -s)

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

# Set linker flags to use the appropriate lib directory with rpath.
LDFLAGS := -L$(LIB_DIR) -Wl,-rpath,'$$ORIGIN/$(LIB_DIR)'

# Choose the library name based on OS and build type.
ifeq ($(BUILD_TYPE),debug)
    # Debug build uses the common library name across platforms.
    LIB_NAME := openiap_clib
else
    ifeq ($(UNAME_S),Linux)
        LIB_NAME := openiap-linux-x64
    else ifeq ($(UNAME_S),Darwin)
        LIB_NAME := openiap-macos-x64
    else
        $(error Unsupported OS: $(UNAME_S))
    endif
endif

# Use the actual library file path to avoid -l prefix issues
LIB := $(LIB_DIR)/lib$(LIB_NAME).so
ifeq ($(UNAME_S),Darwin)
    LIB := $(LIB_DIR)/lib$(LIB_NAME).dylib
endif

# Binary name and source files.
TARGET  := workitem_client
SRCS    := main.c
OBJS    := $(SRCS:.c=.o)

# Add symlink target
.PHONY: all clean run debug symlink

all: symlink $(TARGET)
	@echo "Built $(TARGET) in $(BUILD_TYPE) mode."

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
