# Delegates to a sample's Makefile: make [SAMPLE=<folder>] <target>
SAMPLE ?= tc31-xar-base
SAMPLES := $(sort $(patsubst %/Makefile,%,$(wildcard */Makefile)))
TARGETS := build-image push-image run-containers restart-containers list-containers stop-and-remove-containers container-logs build-image-remote deploy-containers remote-container-logs remote-stop-containers

.DEFAULT_GOAL := help
.PHONY: $(TARGETS) list-samples help

$(TARGETS):
	@test -f "$(SAMPLE)/Makefile" || { echo "Unknown sample '$(SAMPLE)'. Available: $(SAMPLES)"; exit 1; }
	$(MAKE) -C $(SAMPLE) $@

list-samples:
	@echo $(SAMPLES)

help:
	@echo "Usage: make [SAMPLE=<folder>] <target>   (default SAMPLE=$(SAMPLE))"
	@echo "Samples: $(SAMPLES)"
	@echo "Targets: $(TARGETS) list-samples"
	@echo "Run 'make -C <sample> help' for details."
