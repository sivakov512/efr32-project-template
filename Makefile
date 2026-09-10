# SLC generates the CMake project; this file runs everyday development commands.
.DEFAULT_GOAL := build
# Generation and build. SDK version is read from .slcp; SDK and Python (with
# PyYAML) come from SLT. Override if needed.
SLT_PYTHON := $(shell slt where python 2>/dev/null)
PYTHON ?= $(if $(SLT_PYTHON),$(SLT_PYTHON)/bin/python3,python3)
SLC ?= slc
CMAKE ?= cmake
SLC_COPY ?= -cpsdk

# Serial logging. Override PORT when more than one adapter is connected.
PORT ?= $(firstword $(wildcard /dev/cu.usbmodem* /dev/ttyACM* /dev/cu.usbserial* /dev/ttyUSB*))

# Debugging (normally keep these defaults).
GDB ?= arm-none-eabi-gdb
JLINK_GDB_SERVER ?= JLinkGDBServer
GDB_PORT ?= 2331

# Optional source analysis.
CLANG_TIDY ?= clang-tidy
CLANG_FORMAT ?= clang-format
CLANG_TIDY_HEADER_FILTER ?= $(CURDIR)/[^/]+\.h$$

# Reject unsupported overrides; this template always generates GCC projects.
ifneq ($(or $(TOOLCHAIN),gcc),gcc)
$(error Unsupported TOOLCHAIN=$(TOOLCHAIN). This Makefile supports GCC only)
endif

# ---- Derived project settings: no manual editing needed ----
# Standalone maintenance commands do not need the project YAML or SDK.
ifneq ($(filter-out clean check-format reset erase monitor-vcom monitor-rtt monitor-auto,$(or $(MAKECMDGOALS),build)),)
INFO := $(shell $(PYTHON) tools/slcp_info.py 2>&1 || echo __ERROR__)
ifneq ($(filter __ERROR__,$(INFO)),)
$(error $(filter-out __ERROR__,$(INFO)))
endif
SLCP := $(word 1,$(INFO))
PROJECT := $(word 2,$(INFO))
SDK_VERSION := $(word 3,$(INFO))
JLINK_DEVICE ?= $(word 4,$(INFO))
endif
SDK ?= $(shell slt where simplicity-sdk/$(SDK_VERSION) 2>/dev/null)
BUILD_DIR := cmake_gcc/build
OUT := $(BUILD_DIR)/base/$(PROJECT)
BAUD = $(or $(shell awk '/define SL_IOSTREAM_E?USART_VCOM_BAUDRATE/{print $$3}' $(wildcard config/sl_iostream_*usart_vcom_config.h) /dev/null),115200)
LOG_TRANSPORT = $(if $(shell grep -qs 'define APP_LOG_STREAM_TYPE.*_RTT' config/app_log_config.h && echo yes),rtt,vcom)
# One check function, used by each command before it starts work.
require = @$(foreach tool,$(1),command -v "$(tool)" >/dev/null 2>&1 || { echo "ERROR: $(tool) not found. Install it or add its directory to PATH."; exit 1; };)

# Generate / build
.PHONY: generate build regenerate clean

generate:
	$(call require,$(SLC))
	@test -n "$(SDK)" || { echo "ERROR: SDK $(SDK_VERSION) not found. Set SDK=/absolute/path/to/sdk."; exit 1; }
	$(SLC) generate -p "$(SLCP)" --sdk-package-path "$(SDK)" -d . --toolchain gcc -o cmake $(SLC_COPY)
# Clang analysis also needs CMSIS headers omitted by the GCC-only SDK copy.
	@for d in simplicity_sdk_*/cmsis/Core/Include; do test ! -d "$$d" || { \
		cp "$(SDK)/cmsis/Core/Include/cmsis_clang.h" "$$d/" && \
		cp "$(SDK)/cmsis/Core/Include/m-profile/cmsis_clang_m.h" "$$d/m-profile/"; } || exit; done

build:
	$(call require,$(CMAKE) $(PYTHON))
	@test -f cmake_gcc/CMakePresets.json || { echo "ERROR: run make generate first; no generated CMake project."; exit 1; }
	cd cmake_gcc && $(CMAKE) --preset project -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
	$(CMAKE) --build $(BUILD_DIR) --config base --target $(PROJECT) -j
	$(PYTHON) tools/compile_db.py $(BUILD_DIR)

regenerate: generate
	$(MAKE) build

clean:
	rm -rf $(BUILD_DIR) compile_commands.json

# Hardware (these commands access the connected target)
.PHONY: flash flashm reset erase monitor-vcom monitor-rtt monitor-auto debug-server debug zed-debug-config

flash:
	$(call require,commander)
	$(MAKE) build
	commander flash $(OUT).hex

flashm:
	$(call require,commander $(if $(filter vcom,$(LOG_TRANSPORT)),tio))
	$(MAKE) flash
	$(MAKE) monitor-auto

reset:
	$(call require,commander)
	commander device reset

erase:
	$(call require,commander)
	commander device masserase

monitor-vcom:
	$(call require,tio)
	@test -n "$(PORT)" || { echo "ERROR: no serial port found. Set PORT=/dev/..."; exit 1; }
	tio -b $(BAUD) $(PORT)

monitor-rtt:
	$(call require,commander)
	commander rtt connect

monitor-auto:
	$(MAKE) monitor-$(LOG_TRANSPORT)

# Start the server in another terminal before running debug.
debug-server:
	$(call require,$(JLINK_GDB_SERVER))
	$(JLINK_GDB_SERVER) -device $(JLINK_DEVICE) -if SWD -speed auto -port $(GDB_PORT) -nogui

debug:
	$(call require,$(GDB))
	$(MAKE) build
	$(GDB) $(OUT).out -ex "target remote :$(GDB_PORT)" -ex "monitor reset" -ex "load"

# Zed requires absolute paths; keep this generated file out of Git.
zed-debug-config:
	$(call require,$(GDB))
	@mkdir -p .zed
	@printf '%s\n' '[{"label":"Debug (J-Link)","adapter":"GDB","request":"attach",' \
		'"program":"$(CURDIR)/$(OUT).out","target":":$(GDB_PORT)",' \
		'"gdb_path":"$(shell command -v $(GDB))"}]' > .zed/debug.json

# Check application sources only, excluding generated and SDK directories.
PRUNE := \( -type d \( -name build -o -name .git -o -name .cache -o -name .venv \
         -o -name autogen -o -name config -o -name 'cmake_*' -o -name 'simplicity_sdk_*' \) -prune \)
.PHONY: lint check-format check

lint:
	$(call require,$(CLANG_TIDY))
	$(MAKE) build
	find . $(PRUNE) -o -type f -name '*.c' -print0 \
		| xargs -0 $(CLANG_TIDY) --header-filter='$(CLANG_TIDY_HEADER_FILTER)' -p $(BUILD_DIR)/tidy

check-format:
	$(call require,$(CLANG_FORMAT))
	find . $(PRUNE) -o -type f \( -name '*.c' -o -name '*.h' \) -print0 \
		| xargs -0 $(CLANG_FORMAT) --dry-run --Werror

check:
	$(call require,$(CLANG_TIDY) $(CLANG_FORMAT))
	$(MAKE) lint check-format
