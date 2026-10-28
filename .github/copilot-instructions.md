# Copilot Instructions

Sample for running a containerized TwinCAT 3.1 XAR runtime (Debian, `tc31-xar-um`) on a Beckhoff IPC with Beckhoff RT Linux, reachable from TwinCAT Engineering on Windows via ADS-over-MQTT. There is no application code, test suite, or linter — only Docker/Compose/Make config and XML/shell files.

## Build and run

Run on the Linux host from the repo root (usually with `sudo`):

- `make build-image` — builds `tc31-xar-base:latest` (`--no-cache`, `--network host`, uses BuildKit secret `apt` from `apt-config.private/bhf.conf` and named build context `apt-config` → `apt-config.private`). Requires `cp -r apt-config apt-config.private` first. Overridable vars: `REGISTRY`, `IMAGE_OWNER`, `IMAGE_NAME`, `IMAGE_TAG`, `APT_CONFIG_DIR`, `APT_AUTH_CONF`, `DOCKERFILE`, `BUILD_CONTEXT`.
- `make run-containers` / `restart-containers` (down + up) / `list-containers` / `container-logs` / `stop-and-remove-containers` / `push-image`
- Single service restart: `docker compose restart tc31-xar-base`
- Health check inside the runtime container: `tcadstool 127.0.0.1.1.1 state`

## Architecture

- `docker-compose.yaml` defines a fixed network `container-network` (192.168.20.0/24) with two services: `mosquitto` (192.168.20.2, port 1883, config `simple-mosquitto.conf`, anonymous) and `tc31-xar-base` (192.168.20.3, `privileged: true`, mounts `/dev/hugepages`). The runtime image is **not pulled**; it must be built locally first.
- `tc31-xar-base/Dockerfile`: `debian:trixie-slim`; fetches the Beckhoff signing key and replaces Debian apt sources with `deb.beckhoff.com` (via `bhf.list` and `debian.sources.list` from the `apt-config` named build context), authenticated with the secret `apt` netrc file (`bhf.conf`); installs `tc31-xar-um` and `adstool`; copies `TwinCAT/StaticRoutes.xml` and `SysStartupState.reg` into `/etc/TwinCAT/3.1/Target/`.
- `entrypoint.sh` execs `TcSystemServiceUm` with `-i "${AMS_NETID}"` (set in compose, default `15.15.15.15.1.1`).
- ADS-over-MQTT: the container's `StaticRoutes.xml` connects to broker host `mosquitto` (topic `AdsOverMqtt`). The root `mqtt.xml` is a **template for the Windows engineering PC** (copied to `C:\Program Files (x86)\Beckhoff\TwinCAT\3.1\Target\Routes\`); its `ip-address-of-container-host` placeholder must be replaced with the IPC's IP.
- Real-time Ethernet: NICs bound to `vfio-pci` on the host (`TcRteInstall`); `PCI_DEVICES` env var in compose (unset = probe all, `NONE`, or space-separated PCI addresses) controls which are used.

## Conventions

- `apt-config/` (repo root) is the template shared by all samples: it may only contain the placeholder template data (`<mybeckhoff-mail>` / `<mybeckhoff-password>`). Real credentials go only in the gitignored `apt-config.private/`, which every sample must use for building containers.
- If the AMS Net ID, broker name/IP, or port 1883 changes, keep `docker-compose.yaml`, `StaticRoutes.xml`, `mqtt.xml`, and the README (firewall/nftables step, target Net ID) consistent.
- Keep the Makefile targets, `make help` text, and the README "Additional Commands" list in sync.
- `entrypoint.sh` carries an SPDX header (Zero-Clause BSD); keep it POSIX `sh`.
