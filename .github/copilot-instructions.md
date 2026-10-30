# Copilot Instructions

Sample for running a containerized TwinCAT 3.1 XAR runtime (Debian, `tc31-xar-um`) on a Beckhoff IPC with Beckhoff RT Linux, reachable from TwinCAT Engineering on Windows via ADS-over-MQTT. There is no application code, test suite, or linter — only Docker/Compose/Make config and XML/shell files.

## Build and run

Run on the Linux host from the repo root (usually with `sudo`):

- Root `Makefile` delegates to `<sample>/Makefile` via `make [SAMPLE=<folder>] <target>` (default `tc31-xar-base`); each sample Makefile sets `IMAGE_NAME` and includes `../mk/common.mk`, which holds all shared targets/variables. Add shared behavior to `mk/common.mk`, sample-specific behavior to the sample Makefile. Each sample owns its own `docker-compose.yaml`; compose commands run from the sample directory.
- `make build-image` — builds `tc31-xar-base:latest` (`--no-cache`, `--network host`, uses BuildKit secret `apt` from `apt-config.private/bhf.conf` and named build context `apt-config` → `apt-config.private`). Requires `cp -r apt-config apt-config.private` first. Overridable vars: `REGISTRY`, `IMAGE_OWNER`, `IMAGE_NAME`, `IMAGE_TAG`, `APT_CONFIG_DIR`, `APT_AUTH_CONF`, `DOCKERFILE`, `BUILD_CONTEXT`.
- `make run-containers` / `restart-containers` (down + up) / `list-containers` / `container-logs` / `stop-and-remove-containers` / `push-image`
- Remote (needs `apt-config.private/target.conf`, SSH key auth, target user in group `docker`): `make build-image-remote` (`DOCKER_HOST=ssh://…`), `make deploy-containers` (scp of the sample's `DEPLOY_FILES` to `TARGET_DIR/<sample>`, then `docker compose up -d` over ssh), `remote-container-logs`, `remote-stop-containers`. Each sample lists the files its compose setup needs in `DEPLOY_FILES` in its Makefile; bind mounts only work on the remote if those files are deployed.
- Single service restart: `docker compose restart tc31-xar-base`
- Health check inside the runtime container: `tcadstool 127.0.0.1.1.1 state`

## Architecture

- `tc31-xar-base/docker-compose.yaml` pins the Compose project name (`name: tc31-xar-base`) so it doesn't depend on the folder or `-f` path; keep this in every sample's compose file. It defines a fixed network `container-network` (192.168.20.0/24) with two services: `mosquitto` (192.168.20.2, port 1883, config `simple-mosquitto.conf`, anonymous) and `tc31-xar-base` (192.168.20.3, `privileged: true`, mounts `/dev/hugepages`). The runtime image is **not pulled**; it must be built locally first.
- `tc31-xar-base/Dockerfile`: `debian:trixie-slim`; fetches the Beckhoff signing key and replaces Debian apt sources with `deb.beckhoff.com` (via `bhf.list` and `debian.sources.list` from the `apt-config` named build context), authenticated with the secret `apt` netrc file (`bhf.conf`); installs `tc31-xar-um` and `adstool`; copies `TwinCAT/StaticRoutes.xml` and `SysStartupState.reg` into `/etc/TwinCAT/3.1/Target/`.
- `entrypoint.sh` execs `TcSystemServiceUm` with `-i "${AMS_NETID}"` (set in compose, default `15.15.15.3.1.1`).
- ADS-over-MQTT: the container's `StaticRoutes.xml` connects to broker host `mosquitto` (topic `AdsOverMqtt`). `tc31-xar-base/mqtt.xml` is a **template for the Windows engineering PC** (copied to `C:\Program Files (x86)\Beckhoff\TwinCAT\3.1\Target\Routes\`); its `ip-address-of-container-host` placeholder must be replaced with the IPC's IP.
- Samples: `tc31-xar-base` (runtime + Mosquitto), `tc31-xar-motion` (`FROM tc31-xar-base:latest` + `tf5000-nc-ptp-xar`; build arg `BASE_IMAGE`; joins external `container-network` at 192.168.20.4, AMS Net ID `15.15.15.4.1.1`; base image must exist on the build machine), `tc31-xar-motion-nci` (like motion, plus `twincat-xar-nci-classic` and `twincat-xar-nci-gst`; 192.168.20.5, AMS Net ID `15.15.15.5.1.1`) and `tf2000-hmi-server` (**NOT WORKING**, work in progress; TF2000 HMI server; standalone Dockerfile, joins the external `container-network` at 192.168.20.10, ADS via the `mosquitto` broker, AMS Net ID `15.15.15.10.1.1`, HTTPS port 2020 published, local HTTP endpoint 2010 not published). Samples share the network `container-network` (192.168.20.0/24); pick unique IPs and AMS Net IDs. `PRE_UP` in a sample Makefile creates the shared network before `compose up`.
- Real-time Ethernet: NICs bound to `vfio-pci` on the host (`TcRteInstall`); `PCI_DEVICES` env var in compose (unset = probe all, `NONE`, or space-separated PCI addresses) controls which are used.

## Conventions

- `apt-config/` (repo root) is the template shared by all samples: it may only contain the placeholder template data (`<mybeckhoff-mail>` / `<mybeckhoff-password>`). Real credentials go only in the gitignored `apt-config.private/`, which every sample must use for building containers.
- If the AMS Net ID, broker name/IP, or port 1883 changes, keep `docker-compose.yaml`, `StaticRoutes.xml`, `mqtt.xml`, and the README (firewall/nftables step, target Net ID) consistent.
- Host firewall (nftables) docs must keep the forward rule `ip saddr 192.168.20.0/24 ip daddr 192.168.20.0/24 accept` for container-to-container traffic on `container-network` (e.g. runtime to the `mosquitto` broker); restricting the broker ports to `br200` / `eno1` alone blocks the runtimes. Keep `mk/common.mk` targets, the root Makefile `TARGETS` list, the `help` text, and the README "Additional Commands" list in sync.
- The root `README.md` is the guide for `tc31-xar-base` only; leave it as is. Every new sample gets its own `README.md` in its folder with sample-specific explanation and instructions. Touch the root README only to add a short description of the new sample and a link to the sample's README.
- Don't hard-code the repository name (e.g. `TC_XAR_Container_Sample` / `tc_xar_container_sample`) in docs, scripts, or config; use placeholders like `<repository-url>`, relative paths, or the pinned per-sample Compose `name:`.
- Run-time secrets live in `apt-config.private/*.env` (template: `apt-config/hmi.env`), referenced by `ENV_FILE` in a sample Makefile and interpolated in compose via `${VAR:?message}`; never put secrets in compose files, images or committed files.
- `SAMPLES.md` (repo root) lists all samples with their unique IP address and AMS Net ID on `container-network`, sorted by IP; update it whenever a sample is added or its IP/AMS Net ID changes. The AMS Net ID is derived from the IP: `192.168.20.X` → `15.15.15.X.1.1`. Use the next free values for new samples.
- `entrypoint.sh` carries an SPDX header (Zero-Clause BSD); keep it POSIX `sh`.
