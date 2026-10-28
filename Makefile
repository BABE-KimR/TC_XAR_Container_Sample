# Define variables with defaults
REGISTRY ?=
IMAGE_OWNER ?=
IMAGE_NAME ?= tc31-xar-base
IMAGE_TAG ?= latest

IMAGE = $(REGISTRY)$(IMAGE_OWNER)$(IMAGE_NAME):$(IMAGE_TAG)

APT_CONFIG_DIR ?= ./apt-config.private
APT_AUTH_CONF ?= $(APT_CONFIG_DIR)/bhf.conf
DOCKERFILE ?= ./tc31-xar-base/Dockerfile
BUILD_CONTEXT ?= ./tc31-xar-base

.DEFAULT_GOAL := help

build-image:
	@echo "Building Docker image: $(IMAGE)"
	docker build --no-cache --secret id=apt,src=$(APT_AUTH_CONF) --build-context apt-config=$(APT_CONFIG_DIR) --network host -t $(IMAGE) -f $(DOCKERFILE) $(BUILD_CONTEXT)

push-image:
	@echo "Pushing Docker image: $(IMAGE)"
	docker push $(IMAGE)

run-containers:
	@echo "Starting containers..."
	docker compose up -d

restart-containers:
	@echo "Restarting containers..."
	docker compose down
	docker compose up -d

# List all containers managed by Docker Compose
list-containers:
	@echo "Listing containers..."
	docker compose ps -a

# Stop and remove containers managed by Docker Compose
stop-and-remove-containers:
	@echo "Stopping and removing containers..."
	docker compose down

# Show logs for containers managed by Docker Compose
container-logs:
	@echo "Showing container logs..."
	docker compose logs -ft

# Display help information
help:
	@echo "Available targets:"
	@echo "  build-image             Build the Docker image"
	@echo "  push-image              Push the Docker image to the registry"
	@echo "  run-containers          Start containers using Docker Compose"
	@echo "  restart-containers      Restart containers using Docker Compose"
	@echo "  list-containers         List all containers managed by Docker Compose"
	@echo "  stop-and-remove-containers Stop and remove containers managed by Docker Compose"
	@echo "  container-logs          Show logs for containers managed by Docker Compose"
	@echo "  help                    Display this help message"
