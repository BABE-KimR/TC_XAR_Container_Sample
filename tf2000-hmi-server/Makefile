IMAGE_NAME ?= tf2000-hmi-server
DEPLOY_FILES = docker-compose.yaml
# Shared network of all TwinCAT container samples (same settings as tc31-xar-base)
PRE_UP = docker network inspect container-network >/dev/null 2>&1 || docker network create --subnet 192.168.20.0/24 --gateway 192.168.20.1 container-network

ENV_FILE = $(APT_CONFIG_DIR)/hmi.env
POST_UP_MSG = Next steps for tf2000-hmi-server:\n  1. Open TCP 2020 in nftables and restart Docker (README, step 2).\n  2. The server initializes itself on first start; check: sudo make SAMPLE=tf2000-hmi-server container-logs\n  3. Open https://<ipc-address>:2020 in TwinCAT HMI Engineering.\n  4. To re-initialize: sudo make SAMPLE=tf2000-hmi-server stop-and-remove-containers, remove the volume with docker volume rm tf2000-hmi-server_hmi-server-data, then run-containers again.\n  See tf2000-hmi-server/README.md for details.
include ../mk/common.mk
