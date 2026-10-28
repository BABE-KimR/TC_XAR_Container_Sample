# Shared build/run targets for samples. Include from <sample>/Makefile after
# setting IMAGE_NAME; run with the sample directory as working directory
# (e.g. `make -C <sample> build-image`, which the root Makefile does).

COMMON_MK_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
REPO_ROOT := $(abspath $(COMMON_MK_DIR)..)

REGISTRY ?=
IMAGE_OWNER ?=
IMAGE_NAME ?= $(notdir $(CURDIR))
IMAGE_TAG ?= latest

IMAGE = $(REGISTRY)$(IMAGE_OWNER)$(IMAGE_NAME):$(IMAGE_TAG)

# Private copy of the ./apt-config template (see apt-config/README.md)
APT_CONFIG_DIR ?= $(REPO_ROOT)/apt-config.private
APT_AUTH_CONF ?= $(APT_CONFIG_DIR)/bhf.conf

DOCKERFILE ?= Dockerfile
BUILD_CONTEXT ?= .
EXTRA_BUILD_ARGS ?=
# Files copied to the target by deploy-containers (relative to the sample folder)
DEPLOY_FILES ?= docker-compose.yaml
# Optional shell command run before `docker compose up` (e.g. to create a shared network)
PRE_UP ?=
# Optional env file with run-time secrets for docker compose (kept in apt-config.private, never committed)
ENV_FILE ?=
COMPOSE = docker compose $(if $(ENV_FILE),--env-file "$(ENV_FILE)")
# Optional hint printed after the containers were started: one line per \n, no single quotes or %
POST_UP_MSG ?=
POST_UP = $(if $(POST_UP_MSG),@printf '\n$(POST_UP_MSG)\n')

# Optional remote target definition (see apt-config/target.conf)
-include $(APT_CONFIG_DIR)/target.conf
TARGET_PORT ?= 22
TARGET_DIR ?= tc-xar-samples
REMOTE_DIR = $(TARGET_DIR)/$(notdir $(CURDIR))
SSH_ID = $(if $(TARGET_SSH_KEY),-i "$(TARGET_SSH_KEY)")
SSH = ssh -p $(TARGET_PORT) $(SSH_ID) $(TARGET_USER)@$(TARGET_HOST)
SCP = scp -P $(TARGET_PORT) $(SSH_ID)
REMOTE_DOCKER_HOST = ssh://$(TARGET_USER)@$(TARGET_HOST):$(TARGET_PORT)
BUILD_CMD = docker build --no-cache --secret id=apt,src=$(APT_AUTH_CONF) --build-context apt-config=$(APT_CONFIG_DIR) $(EXTRA_BUILD_ARGS) --network host -t $(IMAGE) -f $(DOCKERFILE) $(BUILD_CONTEXT)
# Loads the key into a temporary ssh-agent so the docker CLI's ssh connection can use it
WITH_KEY = $(if $(TARGET_SSH_KEY),ssh-agent sh -c 'ssh-add "$(TARGET_SSH_KEY)" && $(1)',$(1))

.DEFAULT_GOAL := help
.PHONY: build-image push-image run-containers restart-containers list-containers stop-and-remove-containers container-logs check-apt-config check-target check-env build-image-remote deploy-containers remote-container-logs remote-stop-containers help

check-env:
	@test -z "$(ENV_FILE)" || test -f "$(ENV_FILE)" || { echo "Missing $(ENV_FILE). Copy it from $(REPO_ROOT)/apt-config/$(notdir $(ENV_FILE)) and edit it."; exit 1; }

check-apt-config:
	@test -f "$(APT_AUTH_CONF)" || { echo "Missing $(APT_AUTH_CONF). Run: cp -r $(REPO_ROOT)/apt-config $(APT_CONFIG_DIR) and add your myBeckhoff credentials."; exit 1; }

check-target:
	@test -f "$(APT_CONFIG_DIR)/target.conf" || { echo "Missing $(APT_CONFIG_DIR)/target.conf. Copy it from $(REPO_ROOT)/apt-config/target.conf and edit it."; exit 1; }
	@case "$(TARGET_HOST)$(TARGET_USER)" in *ip-address-of-target*|*"<"*|"") echo "Set TARGET_HOST and TARGET_USER in $(APT_CONFIG_DIR)/target.conf"; exit 1;; esac

build-image: check-apt-config
	@echo "Building Docker image: $(IMAGE)"
	$(BUILD_CMD)

# Builds on the target: the build context, secret and apt-config are streamed over SSH
build-image-remote: check-apt-config check-target
	@echo "Building Docker image $(IMAGE) on $(TARGET_USER)@$(TARGET_HOST)"
	$(call WITH_KEY,DOCKER_HOST=$(REMOTE_DOCKER_HOST) $(BUILD_CMD))

# Copies the compose files to the target and starts the containers there
deploy-containers: check-target check-env
	@echo "Deploying to $(TARGET_USER)@$(TARGET_HOST):$(REMOTE_DIR)"
	$(SSH) "$(if $(PRE_UP),$(PRE_UP) && )mkdir -p '$(REMOTE_DIR)'"
	$(SCP) $(DEPLOY_FILES) $(TARGET_USER)@$(TARGET_HOST):'$(REMOTE_DIR)/'
	$(if $(ENV_FILE),$(SCP) "$(ENV_FILE)" $(TARGET_USER)@$(TARGET_HOST):'$(REMOTE_DIR)/.env' && $(SSH) "chmod 600 '$(REMOTE_DIR)/.env'")
	$(SSH) "cd '$(REMOTE_DIR)' && docker compose up -d"
	$(call POST_UP)

remote-container-logs: check-target
	$(SSH) "cd '$(REMOTE_DIR)' && docker compose logs -f"

remote-stop-containers: check-target
	$(SSH) "cd '$(REMOTE_DIR)' && docker compose down"

push-image:
	@echo "Pushing Docker image: $(IMAGE)"
	docker push $(IMAGE)

run-containers: check-env
	@echo "Starting containers..."
	$(PRE_UP)
	$(COMPOSE) up -d
	$(call POST_UP)

restart-containers: check-env
	@echo "Restarting containers..."
	$(COMPOSE) down
	$(PRE_UP)
	$(COMPOSE) up -d
	$(call POST_UP)

list-containers:
	@echo "Listing containers..."
	$(COMPOSE) ps -a

stop-and-remove-containers:
	@echo "Stopping and removing containers..."
	$(COMPOSE) down

container-logs:
	@echo "Showing container logs..."
	$(COMPOSE) logs -ft

help:
	@echo "Available targets:"
	@echo "  build-image                 Build the Docker image ($(IMAGE))"
	@echo "  push-image                  Push the Docker image to the registry"
	@echo "  run-containers              Start containers using Docker Compose"
	@echo "  restart-containers          Restart containers using Docker Compose"
	@echo "  list-containers             List all containers managed by Docker Compose"
	@echo "  stop-and-remove-containers  Stop and remove containers managed by Docker Compose"
	@echo "  container-logs              Show logs for containers managed by Docker Compose"
	@echo "  build-image-remote          Build the image on the target defined in apt-config.private/target.conf"
	@echo "  deploy-containers           Copy compose files to the target and start the containers there"
	@echo "  remote-container-logs       Follow container logs on the target"
	@echo "  remote-stop-containers      Stop and remove the containers on the target"
	@echo "  help                        Display this help message"
