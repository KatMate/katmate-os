# Katmate OS — base image build pipeline (ADR-011, LVM-thin per ADR-010 rev 2026-06)
#
# Layers are LVM thin volumes, NOT files. App-layers are RO-frozen thin
# snapshots of the foundation. Requires root for lvm/mount/chroot:
#     sudo make foundation        # build + freeze vg0/vm_tpl_foundation
#     sudo make app-web           # build + freeze vg0/vm_app_web
#     sudo make app-vault         # build + freeze vg0/vm_app_vault
#     sudo make apps              # all app-<type> layers
#     make clean                  # remove app-layer LVs (root needed in practice)
#
# Targets are .PHONY: LVs are not files, so Make cannot stat a timestamp.
# Each app-layer build refuses to clobber an existing LV — rebuild = drop first.
#
# External prerequisites for the FOUNDATION step only (not the app-layers),
# placed in out/ by their own sub-pipelines:
#     out/linux-image-katmate-microvm-amd64.deb   (custom MicroVM kernel, ADR-005)
#     out/vm-agent                                 (Rust vm-agent binary, ADR-018)
SHELL := /bin/bash
BUILD := build
OUT   := out
KERNEL_VERSION := 6.12.87
KERNEL_VMLINUZ := $(OUT)/vmlinuz-katmate-microvm-amd64-$(KERNEL_VERSION)
KERNEL_SRC_DIR ?= /home/host/katmate-kernels
VM_AGENT   := $(OUT)/vm-agent
APP_TYPES  := web vault
APP_TARGETS := $(addprefix app-,$(APP_TYPES))

.PHONY: all foundation apps clean $(APP_TARGETS)

all: apps

foundation: $(BUILD)/foundation.sh $(KERNEL_VMLINUZ) $(VM_AGENT)
	$(BUILD)/foundation.sh

apps: $(APP_TARGETS)

# app-<type> : RO-frozen thin snapshot vm_app_<type> of the foundation.
# Needs only the foundation LV + its manifest — NOT the kernel or vm-agent
# (those are baked into the foundation).
$(APP_TARGETS): app-%: $(BUILD)/app-layer.sh manifests/%.list
	$(BUILD)/app-layer.sh $*

# clear, guided failure for the kernel hook (foundation step only)
$(KERNEL_VMLINUZ):
	@if [ -f "$(KERNEL_SRC_DIR)/$(notdir $(KERNEL_VMLINUZ))" ]; then \
	  mkdir -p $(OUT); \
	  cp "$(KERNEL_SRC_DIR)/$(notdir $(KERNEL_VMLINUZ))" "$@"; \
	  echo "Copied kernel: $@"; \
	else \
	  echo "MISSING: $@"; \
	  echo "  Custom MicroVM kernel (ADR-005). Expected source:"; \
	  echo "    $(KERNEL_SRC_DIR)/$(notdir $(KERNEL_VMLINUZ))"; \
	  echo "  Build it or set KERNEL_SRC_DIR=/path make foundation"; \
	  exit 1; \
	fi

# vm-agent is Rust now (ADR-018); copy the compiled binary here for the
# foundation build. (App-layers do not use it.)
$(VM_AGENT):
	@echo "MISSING: $@"; \
	echo "  Build the Rust vm-agent and copy the binary here, e.g. from agent/:"; \
	echo "    cargo build --release && cp target/release/vm-agent $(VM_AGENT)"; \
	exit 1

# Remove app-layer LVs (foundation is left intact). Deactivate first because
# RO-frozen thin LVs may need it; ignore absence.
clean:
	@for t in $(APP_TYPES); do \
	  lv=vg0/vm_app_$$t; \
	  if lvs $$lv >/dev/null 2>&1; then \
	    echo "Removing $$lv"; \
	    lvchange -an $$lv 2>/dev/null || true; \
	    lvremove -f $$lv; \
	  fi; \
	done
