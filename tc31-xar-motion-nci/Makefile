IMAGE_NAME ?= tc31-xar-motion-nci
DEPLOY_FILES = docker-compose.yaml
# Shared network of all TwinCAT container samples (same settings as tc31-xar-base)
PRE_UP = docker network inspect container-network >/dev/null 2>&1 || docker network create --subnet 192.168.20.0/24 --gateway 192.168.20.1 container-network
POST_UP_MSG = Next steps for tc31-xar-motion-nci:\n  1. The runtime has AMS Net ID 15.15.15.5.1.1 and reaches TwinCAT Engineering via the mosquitto broker (ADS-over-MQTT).\n  2. Check the runtime: sudo docker exec tc31-xar-motion-nci tcadstool 127.0.0.1.1.1 state\n  3. Real-time Ethernet (EtherCAT) needs a NIC bound to vfio-pci, see tc31-xar-motion-nci/README.md.\n  See tc31-xar-motion-nci/README.md for details.

include ../mk/common.mk
