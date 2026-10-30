# TwinCAT 3.1 XAR runtime with motion (TF5000 NC PTP)

Runtime container built on top of the [`tc31-xar-base`](../README.md) image. It adds the Debian package `tf5000-nc-ptp-xar` (TwinCAT 3 NC PTP, point-to-point motion) from the Beckhoff package server, so the runtime can run TwinCAT projects with NC axes. Everything else (entrypoint, `TcSystemServiceUm`, ADS-over-MQTT route to the broker `mosquitto`) is inherited from the base image.

- Container `tc31-xar-motion`: 192.168.20.4 on `container-network`, AMS Net ID `15.15.15.4.1.1`, ADS via the `mosquitto` broker.
- The sample can be deployed independently of the other samples, but **requires** the broker from the [`mosquitto-broker`](../mosquitto-broker/README.md) sample (container `mosquitto` on `container-network`), which must be started separately with its own `make` / compose. No other sample provides a broker. The network is created automatically if it does not exist yet.

**Only one TwinCAT runtime can use the real-time resources of a host.** Running `tc31-xar-motion` next to the `tc31-xar-base` runtime on the same IPC is only sensible if at most one of them uses real-time Ethernet (set `PCI_DEVICES=NONE` for the other) and the real-time cores are not shared. Typically you start the `mosquitto-broker` sample and use `tc31-xar-motion` as the runtime.

## Prerequisites

- Beckhoff IPC with Beckhoff RT Linux, Docker and `make` as described in the [main README](../README.md), including its firewall step for MQTT (port 1883).
- The image `tc31-xar-base:latest` must exist **on the machine that builds** `tc31-xar-motion`. Build it first, see [main README](../README.md), step 1 (for remote builds use `make build-image-remote` for `tc31-xar-base` first, so the image is on the target).
- A private copy of the apt configuration with your myBeckhoff credentials, see [`apt-config/README.md`](../apt-config/README.md):

  ```bash
  cp -r apt-config apt-config.private
  nano apt-config.private/bhf.conf
  ```
- The Windows engineering PC is configured for ADS-over-MQTT as in the main README (step 4, `tc31-xar-base/mqtt.xml`).

## 1. Build the image

From the repository root, on the IPC:

```bash
sudo make SAMPLE=tc31-xar-base build-image     # once, if the base image does not exist yet
sudo make SAMPLE=tc31-xar-motion build-image
```

Or from a Windows PC / any machine with SSH access to the IPC, using `apt-config.private/target.conf` (see [`apt-config/README.md`](../apt-config/README.md), and [Windows with WSL2](../docs/windows-wsl2-build.md)):

```bash
make SAMPLE=tc31-xar-base build-image-remote
make SAMPLE=tc31-xar-motion build-image-remote
```

To use a different base image, build with `EXTRA_BUILD_ARGS="--build-arg BASE_IMAGE=<image>"`.

## 2. Start the containers

The broker must be running. If it is not, start the `mosquitto-broker` sample first (separate compose, not part of this sample):

```bash
sudo make SAMPLE=mosquitto-broker run-containers
```

Then start the motion runtime:

```bash
sudo make SAMPLE=tc31-xar-motion run-containers
```

Or deploy remotely (copies `docker-compose.yaml` to the target and starts it there):

```bash
make SAMPLE=tc31-xar-motion deploy-containers
```

Check the runtime:

```bash
sudo make SAMPLE=tc31-xar-motion list-containers
sudo docker exec tc31-xar-motion tcadstool 127.0.0.1.1.1 state
```

## 3. Connect with TwinCAT Engineering

On the Windows engineering PC the target `15.15.15.4.1.1` appears next to the other containers (see main README, step 4, for the `mqtt.xml` route). Activate your project with NC axes on this target.

## 4. Real-time Ethernet (EtherCAT)

This sample passes **PCI device `0000:02:00.0`** to the container for EtherCAT. On the reference setup (Beckhoff C6030-0080, see the [reference setup](../docs/reference-setup.md)) this is **LAN3 (bottom left on the rear, interface `enp2s0`)**. Keep this port isolated from the corporate network and connect only the EtherCAT devices to it.

1. On the host, check the NICs with `sudo TcRteInstall -l` and bind the port to `vfio-pci` if it is not yet (it disappears from the host network stack): `sudo TcRteInstall -b 0000:02:00.0`.
2. Allocate hugepages on the host (required by the real-time Ethernet driver; without them the log shows `EAL: Cannot get hugepage information.` and TwinCAT reports `Failed to connect to network adapter!`). Check with `grep -i huge /proc/meminfo`; `HugePages_Total` must be above 0:

   ```bash
   echo 512 | sudo tee /proc/sys/vm/nr_hugepages
   echo "vm.nr_hugepages=512" | sudo tee /etc/sysctl.d/90-hugepages.conf   # persist across reboots
   ```

3. Keep the TwinCAT runtime of the host away from the container's port. The host runtime (`TcSystemServiceUm`) probes all `vfio-pci` ports at start and otherwise claims `0000:02:00.0`, so the container gets `Cannot open /dev/vfio/<n>: Device or resource busy`. Either disable it (`sudo systemctl stop TcSystemServiceUm && sudo systemctl disable TcSystemServiceUm`), or restrict it to other ports (or `NONE`) with a systemd drop-in, e.g. LAN4 (`0000:03:00.0`):

   ```bash
   sudo mkdir -p /etc/systemd/system/TcSystemServiceUm.service.d
   sudo tee /etc/systemd/system/TcSystemServiceUm.service.d/override.conf <<'EOF'
   [Service]
   Environment=PCI_DEVICES=0000:03:00.0
   EOF
   sudo systemctl daemon-reload && sudo systemctl restart TcSystemServiceUm
   sudo fuser -v /dev/vfio/14   # the group of the container's port must not be held (group number may differ)
   ```
4. Start the container; it uses `0000:02:00.0` by default:

   ```bash
   sudo make SAMPLE=tc31-xar-motion restart-containers
   ```

To use another port, set `PCI_DEVICES` (space-separated for several, `NONE` for none), e.g. `sudo PCI_DEVICES=0000:03:00.0 make SAMPLE=tc31-xar-motion restart-containers` (LAN4, `enp3s0`), or change the default in `PCI_DEVICES=${PCI_DEVICES:-0000:02:00.0}` in `docker-compose.yaml`. On other hardware, look up the location with `sudo TcRteInstall -l`.

See the main README (step 5) for details on `TcRteInstall`.

## Configuration

- `AMS_NETID` in `docker-compose.yaml`: unique AMS Net ID of this runtime. If you change it, also use the new ID in TwinCAT Engineering.
- The fixed IP `192.168.20.4` must be free on `container-network`.
- `BASE_IMAGE` (build argument): base image, default `tc31-xar-base:latest`.

## Troubleshooting

- **`pull access denied` / `FROM tc31-xar-base:latest` not found:** build `tc31-xar-base` first on the machine that runs the build.
- **`401` / authentication errors during `apt-get`:** check the credentials in `apt-config.private/bhf.conf`.
- **`Unable to locate package tf5000-nc-ptp-xar`:** check your myBeckhoff account has access to the package, and look up the exact name with `apt search tf5000` in the container or on the IPC.
- **Target not visible in TwinCAT Engineering:** check that the broker `mosquitto` runs, the Windows `mqtt.xml` points to the IPC, and the AMS Net ID is unique.
- **`Failed to connect to network adapter!` / `EAL: Cannot get hugepage information.`:** the real-time Ethernet driver needs hugepages on the host. Check `grep -i huge /proc/meminfo` (`HugePages_Total` must be above 0) and that `/dev/hugepages` is a mounted `hugetlbfs`. Allocate with `echo 512 | sudo tee /proc/sys/vm/nr_hugepages` (permanent: `vm.nr_hugepages=512` in `/etc/sysctl.d/`) and restart the container. Also make sure the EtherCAT device in the TwinCAT project uses the real-time adapter with PCI `0000:02:00.0` of target `15.15.15.4.1.1`.
- **`enp2s0` is not visible in the container:** expected. A NIC bound to `vfio-pci` has no Linux interface; TwinCAT uses it by PCI address (`0000:02:00.0`) and lists it as a real-time Ethernet compatible device.
- **`EAL: Cannot open /dev/vfio/<n>: Device or resource busy` / `PCI_BUS: Requested device 0000:02:00.0 cannot be used`:** another process already holds the VFIO group of the port (only one process can). Find it with `sudo fuser -v /dev/vfio/<n>`, and check `ls /sys/kernel/iommu_groups/<n>/devices/` for other devices in the same group. Typical causes are the TwinCAT runtime installed on the host, which probes all `vfio-pci` NICs at start even when it is not used (`sudo systemctl stop TcSystemServiceUm && sudo systemctl disable TcSystemServiceUm`; if unsure of the unit name use `systemctl list-units --all | grep -i -E "tc|twincat"`), another TwinCAT container with `PCI_DEVICES` unset or the same port (set `PCI_DEVICES=NONE` there), or a stale container (`sudo docker ps -a`). Then restart with `sudo make SAMPLE=tc31-xar-motion restart-containers`.
