# Katmate OS — base image build pipeline (ADR-011)
#
# Requires root for nbd/mount/chroot. Run with sudo:
#     sudo make foundation      # build out/foundation.qcow2
#     sudo make apps            # build all app-<type> overlays
#     sudo make                 # = apps (foundation built first as a prerequisite)
#     make clean                # remove build outputs (no root needed)
#
# External prerequisites (placed in out/ by their own sub-pipelines, not built here):
#     out/linux-image-katmate-microvm-amd64.deb   (custom MicroVM kernel, ADR-005)
#     out/vm-agent                                 (compiled vm-agent binary)

SHELL := /bin/bash
BUILD := build
OUT   := out

KERNEL_DEB := $(OUT)/linux-image-katmate-microvm-amd64.deb
VM_AGENT   := $(OUT)/vm-agent

FOUNDATION := $(OUT)/foundation.qcow2
APP_TYPES  := web vault
APP_IMAGES := $(addprefix $(OUT)/app-,$(addsuffix .qcow2,$(APP_TYPES)))

COMMON := $(BUILD)/config.sh $(BUILD)/lib.sh

.PHONY: all foundation apps clean

all: apps

foundation: $(FOUNDATION)

apps: $(APP_IMAGES)

$(FOUNDATION): $(BUILD)/foundation.sh $(COMMON) $(KERNEL_DEB) $(VM_AGENT)
	$(BUILD)/foundation.sh

# each app overlay depends on the foundation and its own manifest
$(OUT)/app-%.qcow2: $(BUILD)/app-layer.sh $(COMMON) manifests/%.list $(FOUNDATION)
	$(BUILD)/app-layer.sh $*

# clear, guided failures for the two external hooks
$(KERNEL_DEB):
	@echo "MISSING: $@"; \
	echo "  Build the MicroVM kernel (Debian LTS sources + katmate-microvm config, ADR-005)"; \
	echo "  and place the linux-image .deb at the path above."; \
	echo "  TODO: dedicated kernel build sub-pipeline."; \
	exit 1

$(VM_AGENT):
	@echo "MISSING: $@"; \
	echo "  Build ../vm-agent (C) and copy the binary here, e.g.:"; \
	echo "    gcc -O2 -Wall -o $(VM_AGENT) ../vm-agent/vm-agent.c"; \
	exit 1

clean:
	rm -f $(FOUNDATION) $(OUT)/app-*.qcow2 $(OUT)/vmlinuz-katmate-microvm
