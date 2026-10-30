# TwinCAT 3.1 XAR runtime with motion and NCI (TF5000 NC PTP, NCI classic, NCI GST)

Runtime container built on top of the [`tc31-xar-base`](../README.md) image. It adds the Debian packages `tf5000-nc-ptp-xar` (TwinCAT 3 NC PTP, point-to-point motion), `twincat-xar-nci-classic` and `twincat-xar-nci-gst` (NCI) from the Beckhoff package server. Everything else (entrypoint, `TcSystemServiceUm`, ADS-over-MQTT route to the broker `mosquitto`) is inherited from the base image.

It is the same as [`tc31-xar-motion`](../tc31-xar-motion/README.md) plus the NCI packages.

- Container `tc31-xar-motion-nci`: 192.168.20.5 on `container-network`, AMS Net ID `15.15.15.5.1.1`, ADS via the `mosquitto` broker.
- The sample can be deployed independently of the other samples, but **requires** the broker from the [`mosquitto-broker`](../mosquitto-broker/README.md) sample (container `mosquitto` on `container-network`), which must be started separately with its own `make` / compose. No other sample provides a broker. The network is created automatically if it does not exist yet.

**Only one TwinCAT runtime can use the real-time resources of a host.** Running this sample next to `tc31-xar-base` or `tc31-xar-motion` on the same IPC is only sensible if at most one of them uses real-time Ethernet (set `PCI_DEVICES=NONE` for the others) and the real-time cores are not shared.

## Prerequisites

- Beckhoff IPC with Beckhoff RT Linux, Docker and `make` as described in the [main README](../README.md), including its firewall step for MQTT (port 1883).
- The image `tc31-xar-base:latest` must exist **on the machine that builds** this sample (see [main README](../README.md), step 1; for remote builds use `make build-image-remote` for `tc31-xar-base` first).
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
sudo make SAMPLE=tc31-xar-motion-nci build-image
```

Or remotely via SSH (see [`apt-config/README.md`](../apt-config/README.md)):

```bash
make SAMPLE=tc31-xar-base build-image-remote
make SAMPLE=tc31-xar-motion-nci build-image-remote
```

To use a different base image, build with `EXTRA_BUILD_ARGS="--build-arg BASE_IMAGE=<image>"`.

## 2. Start the containers

The broker must be running. If it is not, start the `mosquitto-broker` sample first (separate compose, not part of this sample):

```bash
sudo make SAMPLE=mosquitto-broker run-containers
```

Then start the runtime:

```bash
sudo make SAMPLE=tc31-xar-motion-nci run-containers
```

Or deploy remotely:

```bash
make SAMPLE=tc31-xar-motion-nci deploy-containers
```

Check the runtime:

```bash
sudo make SAMPLE=tc31-xar-motion-nci list-containers
sudo docker exec tc31-xar-motion-nci tcadstool 127.0.0.1.1.1 state
```

## 3. Connect with TwinCAT Engineering

On the Windows engineering PC the target `15.15.15.5.1.1` appears next to the other containers (see main README, step 4, for the `mqtt.xml` route).

## 4. Real-time Ethernet (EtherCAT)

No EtherCAT network interface is configured in this sample; you must bind one yourself. To give the container a port for EtherCAT:

1. On the host, list the NICs with `sudo TcRteInstall -l` and bind a NIC that is **not** your primary connection: `sudo TcRteInstall -b <PCI device Location>` (it moves to `vfio-pci` and disappears from the host network stack).
2. Optional: in the `environment:` section of `docker-compose.yaml` set `PCI_DEVICES=<PCI device Location>` (space-separated for several). If unset, all NICs bound to `vfio-pci` are used.
3. Restart the container.

Bind a NIC to `vfio-pci` on the host as described in the main README (step 5) and restart the container (`sudo make SAMPLE=tc31-xar-motion-nci restart-containers`). `PCI_DEVICES` in `docker-compose.yaml` selects the controllers (unset: probe all, `NONE`, or a list of PCI addresses).

## Configuration

- `AMS_NETID` in `docker-compose.yaml`: unique AMS Net ID of this runtime. If you change it, also use the new ID in TwinCAT Engineering.
- The fixed IP `192.168.20.5` must be free on `container-network`.
- `BASE_IMAGE` (build argument): base image, default `tc31-xar-base:latest`.

## Troubleshooting

- **`FROM tc31-xar-base:latest` not found / pull access denied:** build `tc31-xar-base` first on the machine that runs the build.
- **`401` / authentication errors during `apt-get`:** check the credentials in `apt-config.private/bhf.conf`.
- **`Unable to locate package ...`:** check your myBeckhoff account has access, and look up exact names with `apt search nci` / `apt search tf5000`.
- **Target not visible in TwinCAT Engineering:** check that the broker `mosquitto` runs, the Windows `mqtt.xml` points to the IPC, and the AMS Net ID is unique.
