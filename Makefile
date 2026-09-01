SHELL := /bin/bash

# Always run `hf` via pipx to avoid relying on local `hf` installations.
hf := pipx run --spec "huggingface_hub[cli]" hf

SNAP_NAME ?= qwen3
ENGINE ?= cpu

MEDIATEK_MODEL_URL := https://mediatek-aiot.s3.ap-southeast-1.amazonaws.com/aiot/download/iot-ai-hub/model-zoo/gai/genio-360-360p-420-520-720/qwen3-8b.zip

.PHONY: all help init build install upload smoke-test install-deps init-submodules download-models download-model-8b download-model-8b-mediatek

all: help

#
# Main targets
#

help: ## Show this help message
	@echo "Usage: make <target>"
	@echo
	@echo "Targets:"
	@# List all targets with descriptions (lines starting with '##'):
	@grep -E '^[a-zA-Z0-9_-]+:.*## .*$$' $(MAKEFILE_LIST) | \
		sort | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  %-11s %s\n", $$1, $$2}'

init: init-submodules install-deps download-models ## Initialize the build environment (dependencies, model weights, submodules, etc.)

build: ## Build the snap
	./dev/build.sh

install: ## Install the snap
	./dev/install.sh

upload: ## Upload the snap
	./dev/upload.sh

smoke-test: ## Run smoke tests (override with SNAP_NAME=... ENGINE=...)
	sudo ./dev/smoke-test.sh $(SNAP_NAME) $(ENGINE)

#
# Supporting targets
#

install-deps:
	@echo "Installing dependencies..."
	@# Ensure pipx is available for running the hf CLI.
	@command -v pipx >/dev/null 2>&1 || { \
		sudo apt-get update; \
		sudo apt-get install -y pipx; \
	}

init-submodules:
	@echo "Initializing submodules..."
	@if git submodule status | grep -q '^-'; then \
		git submodule update --init; \
	fi

download-models: download-model-8b download-model-8b-mediatek

download-model-8b:
	@echo "Downloading Qwen3-8B-Q4_K_M model weights..."
	$(hf) download unsloth/Qwen3-8B-GGUF Qwen3-8B-Q4_K_M.gguf \
		--local-dir components/model-8b-q4-k-m-gguf/

download-model-8b-mediatek:
	@echo "Downloading MediaTek NPU-optimized Qwen3-8B model weights..."
	@command -v bsdtar >/dev/null 2>&1 || { \
		sudo apt-get update; \
		sudo apt-get install -y libarchive-tools; \
	}
	rm -rf components/model-8b-mediatek
	mkdir -p components/model-8b-mediatek
	set -o pipefail && curl -L "$(MEDIATEK_MODEL_URL)" \
		| bsdtar -xf - -C components/model-8b-mediatek --strip-components=1 \
			'qwen3-8b/2048c/*' 'qwen3-8b/tokenizer/*' 'qwen3-8b/scripts/config-yocto_np8-qwen3-8b.yaml'
	# Swap MediaTek's baked-in Yocto rootfs path for the $$SNAP_COMPONENT_DIR
	# placeholder that engines/mediatek-npu/server substitutes at runtime.
	sed 's#/usr/share/llm/qwen3-8b#$$SNAP_COMPONENT_DIR#g' \
		components/model-8b-mediatek/scripts/config-yocto_np8-qwen3-8b.yaml \
		> components/model-8b-mediatek/config.yaml
	rm -rf components/model-8b-mediatek/scripts
