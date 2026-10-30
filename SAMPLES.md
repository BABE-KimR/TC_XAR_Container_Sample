# Samples, IP addresses and AMS Net IDs

All samples share the Docker network `container-network` (192.168.20.0/24, gateway 192.168.20.1). Every container needs a **unique IP address** and a **unique AMS Net ID**. Update this list whenever a sample is added, changed or removed.

| Sample | Container | IP address | AMS Net ID | Published ports | Status |
|---|---|---|---|---|---|
| `mosquitto-broker` | `mosquitto` | 192.168.20.2 | n/a (MQTT broker) | 1883 | working, must be started separately, required by all other samples |
| `tc31-xar-base` | `tc31-xar-base` | 192.168.20.3 | 15.15.15.3.1.1 | none | working |
| `tc31-xar-motion` | `tc31-xar-motion` | 192.168.20.4 | 15.15.15.4.1.1 | none | working |
| `tc31-xar-motion-nci` | `tc31-xar-motion-nci` | 192.168.20.5 | 15.15.15.5.1.1 | none | tested, NCI folder fails |
| `tf2000-hmi-server` | `tf2000-hmi-server` | 192.168.20.10 | 15.15.15.10.1.1 | 2020 | NOT WORKING |

Reserved: 192.168.20.1 (network gateway).

Next free values: IP address 192.168.20.6, AMS Net ID `15.15.15.6.1.1`.

Keep the table sorted by IP address. The AMS Net ID is derived from the IP address: `192.168.20.X` → `15.15.15.X.1.1`.

When adding a sample, pick the next free values, enter them here, and use the same values in the sample's `docker-compose.yaml`, `Makefile` messages and `README.md`.
