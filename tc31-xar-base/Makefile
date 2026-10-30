IMAGE_NAME ?= tc31-xar-base
DEPLOY_FILES = docker-compose.yaml
# The MQTT broker is not part of this sample: start the mosquitto-broker sample first (see README).
# Shared network of all TwinCAT container samples
PRE_UP = docker network inspect container-network >/dev/null 2>&1 || docker network create --subnet 192.168.20.0/24 --gateway 192.168.20.1 container-network

include ../mk/common.mk
