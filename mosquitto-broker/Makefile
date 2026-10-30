IMAGE_NAME ?= mosquitto-broker
DEPLOY_FILES = docker-compose.yaml simple-mosquitto.conf secure
# Shared network of all TwinCAT container samples (same settings as tc31-xar-base)
PRE_UP = docker network inspect container-network >/dev/null 2>&1 || docker network create --subnet 192.168.20.0/24 --gateway 192.168.20.1 container-network
POST_UP_MSG = Next steps for mosquitto-broker:\n  1. The broker listens on port 1883 (anonymous, firewall: br200 only) and 8883 (TLS, user/password, firewall: eno1 and br200, not for ADS-over-MQTT); 192.168.20.2 on container-network, container name mosquitto.\n  2. Create the TLS files and the password file in mosquitto-broker/secure and allow the ports in the host firewall, see mosquitto-broker/README.md.\n  3. Check the broker: sudo docker ps --filter name=mosquitto\n  See mosquitto-broker/README.md for details.

include ../mk/common.mk
