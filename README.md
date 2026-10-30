# About this Repository

This repository provides a step-by-step guide to build and deploy a containerized TwinCAT 3.1 XAR runtime environment using Docker on a Beckhoff IPC.

With this sample, you will learn how to:

- Build and configure a TwinCAT XAR container image.
- Set up secure communication using ADS-over-MQTT.
- Manage containers with Docker Compose and Makefile automation.
- Connect to the containerized TwinCAT runtime with TwinCAT Engineering.
- Configure real-time Ethernet communication (optional).

Here’s a high-level overview of what the completed setup will look like:

![](./docs/setup-overview.drawio.svg)

---

## **Reference setup**

The hardware and network interface layout used for development is described in [docs/reference-setup.md](docs/reference-setup.md).

Instructions to install a Portainer web UI and to replace containers on the IPC are in [docs/portainer-and-containers.md](docs/portainer-and-containers.md).

---

## **Other samples**

- [`mosquitto-broker`](mosquitto-broker/README.md) — the Mosquitto MQTT broker for ADS-over-MQTT. **Required by all other samples**, it must be started separately with its own `make` / compose, no other sample starts a broker.
- [`tc31-xar-motion`](tc31-xar-motion/README.md) — TwinCAT runtime based on the `tc31-xar-base` image with TF5000 NC PTP (motion) installed.
- [`tc31-xar-motion-nci`](tc31-xar-motion-nci/README.md) — like `tc31-xar-motion`, plus NCI (`twincat-xar-nci-classic`, `twincat-xar-nci-gst`).
- [`tf2000-hmi-server`](tf2000-hmi-server/README.md) — **NOT WORKING (work in progress):** TwinCAT 3 HMI Server (TF2000) container that shares the container network with the TwinCAT runtime and can be deployed independently.

---

## **How to get support**

Should you have any questions regarding the provided sample code, please contact your local Beckhoff support team. Contact information can be found on the official Beckhoff website at https://www.beckhoff.com/contact/.

---

## **Using the sample**

Before you begin, make sure your environment meets the following prerequisites:

**Beckhoff IPC as Beckhoff RT Linux host:**
- [Setup and Install](https://infosys.beckhoff.com/english.php?content=../content/1033/beckhoff_rt_linux/17350447499.html) the Beckhoff Real-Time Linux® Distribution on a supported IPC.
- [Configure access to Beckhoff package server](https://infosys.beckhoff.com/english.php?content=../content/1033/beckhoff_rt_linux/17350408843.html)
- Install the required host packages from the default Debian package sources:

```bash
sudo apt update
sudo apt install --yes docker.io docker-compose make tcsysconf
```

**Windows Engineering PC:**
- A separate Windows PC with [TwinCAT 3 Engineering (XAE)](https://www.beckhoff.com/en-us/products/automation/twincat/) installed to connect to and program the containerized runtime.
- Network connectivity between the Windows PC and the Beckhoff IPC running Beckhoff RT Linux.

**Beckhoff Account:**
- Valid [myBeckhoff](https://www.beckhoff.com/mybeckhoff/) credentials to access the Beckhoff package server at `https://deb.beckhoff.com`.

**Note:** This sample is designed for Beckhoff Industrial PCs running Beckhoff Real-Time Linux. While the Docker image may build on generic Debian systems, real-time functionality and hardware access require Beckhoff-supported hardware and the RT Linux distribution.

Unless a step explicitly says otherwise, run the Linux commands below on the Beckhoff IPC running Beckhoff RT Linux from the repository root directory.

Once the prerequisites are in place, you can follow these steps to build and deploy the TwinCAT XAR container:

## **1. Build the container image**

During the image build process, TwinCAT for Linux® will be downloaded from `https://deb.beckhoff.com`.

   a. The `./apt-config` folder is a shared template for all samples and must only ever contain the template data. Do not edit it. Instead, create a private copy named `apt-config.private` (already listed in `.gitignore`) and put your valid myBeckhoff credentials there, replacing `<mybeckhoff-mail>` and `<mybeckhoff-password>`:

   ```bash
   cp -r ./apt-config ./apt-config.private
   nano ./apt-config.private/bhf.conf
   ```

   All samples use `apt-config.private` when building a container image. Never commit real credentials.

   b. Build the Docker image. You can use the Makefile wrapper (recommended) or the direct docker command:

   **Option A: Using Makefile (from repository root)**
   ```bash
   sudo make build-image
   ```

   **Option B: Using docker directly**
   ```bash
   cd tc31-xar-base
   sudo docker build --secret id=apt,src=../apt-config.private/bhf.conf --build-context apt-config=../apt-config.private --network host -t tc31-xar-base .
   cd ..  # Return to repository root for subsequent steps
   ```

   To build on a Windows PC instead, see [Building the container images on Windows with WSL2](docs/windows-wsl2-build.md).

   c. Verify the image was built successfully:
   ```bash
   sudo docker images
   ```
   You should see an entry with repository `tc31-xar-base` and tag `latest` in the output.

## **2. Set up firewall rules for MQTT**

On the **Beckhoff IPC running Beckhoff RT Linux that will run Docker**, allow incoming TCP connections to the Mosquitto broker of the [`mosquitto-broker`](mosquitto-broker/README.md) sample so ADS-over-MQTT can reach it: port `1883` (anonymous) **only on the bridge adapter `br200`**. Port `8883` (TLS, user name and password, no anonymous access) on `eno1` and `br200` is not used for ADS-over-MQTT, only for other communication. Port 8883 needs a certificate and a password file, see the sample's README.

Create `/etc/nftables.conf.d/60-mosquitto-container.conf` with the following content:

```
sudo nano /etc/nftables.conf.d/60-mosquitto-container.conf
```

```nft
table inet filter {
  chain input {
    iifname "br200" tcp dport 1883 accept
    iifname { "br200", "eno1" } tcp dport 8883 accept
  }
  chain forward {
    type filter hook forward priority 0; policy drop;
    # Traffic between the containers on container-network (runtimes to the broker)
    ip saddr 192.168.20.0/24 ip daddr 192.168.20.0/24 accept
    iifname "br200" tcp dport 1883 accept
    iifname { "br200", "eno1" } tcp dport 8883 accept
    oifname "br200" tcp sport 1883 accept
    oifname { "br200", "eno1" } tcp sport 8883 accept
  }
}
```

The rule `ip saddr 192.168.20.0/24 ip daddr 192.168.20.0/24 accept` is **required**: the `forward` chain drops everything else, including the traffic between the containers on `container-network` (for example a TwinCAT runtime connecting to the broker `mosquitto`). Without it the runtimes cannot connect to the broker, even though both containers are healthy and the broker log shows no connection from the runtime. If you change the subnet of `container-network`, adapt the rule.

Save the file by pressing <kbd>Ctrl</kbd>+<kbd>o</kbd> and <kbd>Enter</kbd>.
Then close the editor via <kbd>Ctrl</kbd>+<kbd>x</kbd> and <kbd>Enter</kbd>.

Apply the rules by reloading the Beckhoff RT Linux nftables configuration, which already includes `/etc/nftables.conf.d/*`:

```bash
sudo systemctl reload nftables
```

Verify the rules were applied:

```bash
sudo nft list ruleset
```

You should see rules that reference TCP ports `1883` and `8883` with the interface names `br200` and `eno1` in the output, in the input and forward chains.

Because reloading nftables flushes the Docker-managed firewall rules, restart the Docker service afterwards so Docker can recreate its network rules before you start the sample containers:

```bash
sudo systemctl restart docker
```

**Note:** The input chain of Beckhoff RT Linux drops traffic that is not explicitly allowed. If the IPC also hosts other services that need inbound traffic, for example a libvirt virtual machine that gets its IP address via DHCP from the host's `dnsmasq`, add rules for them to the persistent file in `/etc/nftables.conf.d/`. A rule added manually with `nft insert rule` is lost on the next `systemctl reload nftables`. For a VM on the libvirt bridge `br200`:

```nft
table inet filter {
  chain input {
    # Allow DHCP requests from VMs on the libvirt bridge br200
    iifname "br200" udp dport 67 accept
  }
}
```

Validate with `sudo nft -c -f /etc/nftables.conf` before reloading. Without such a rule, the VM does not get an address and falls back to an APIPA address (`169.254.x.x`).

## **3. Start the containers**

The sample includes a `tc31-xar-base/docker-compose.yaml` file to simplify the process of creating a container network and starting the TwinCAT runtime container.

**Required:** the MQTT broker is not started by this sample. Start the [`mosquitto-broker`](mosquitto-broker/README.md) sample first, on this host or on another system (from the repository root: `sudo make SAMPLE=mosquitto-broker run-containers`). The Windows engineering PC and the runtime both connect to this broker, see step 4.

From the repository root directory, start the containers:

```bash
sudo docker compose -f tc31-xar-base/docker-compose.yaml up -d
```

Or using the Makefile:

```bash
sudo make run-containers
```

Verify the containers are running:

```bash
sudo docker compose -f tc31-xar-base/docker-compose.yaml ps
# Or: sudo make list-containers
```

You should see the `tc31-xar-base` container with status "Up" (and, if the broker runs on this host, `mosquitto` from the `mosquitto-broker` sample). Check the logs if any container is not running:

```bash
sudo docker compose -f tc31-xar-base/docker-compose.yaml logs
# Or: sudo make container-logs
```

If starting the containers reports `pull access denied for tc31-xar-base`, go back to Step 1 and confirm that the local image `tc31-xar-base:latest` was built successfully. The Compose file expects that image to exist locally before the sample is started.

At this point, the Linux-host side of the sample is ready. The remaining ADS-over-MQTT setup moves to the Windows engineering PC, except for the quick host-IP lookup in step 4(a).

## **4. Configure ADS-over-MQTT connections**

To connect your TwinCAT Engineering system (running on Windows) via ADS-over-MQTT with the containerized TwinCAT runtime:

   a. On your **Beckhoff IPC running Beckhoff RT Linux**, list the network interfaces and their IP addresses:
   ```bash
   ip --brief address
   ```
   In the output, look for the network interface that your Windows engineering PC can reach. Use its IPv4 address from the `inet` column when updating `mqtt.xml`. If the Beckhoff IPC has multiple network interfaces, choose the one that is connected to the same network as your Windows engineering PC.

   b. On your **Windows engineering PC**, edit the `tc31-xar-base/mqtt.xml` template from this repository. Replace `ip-address-of-container-host` with the IP address from step (a) — this is the IP address of your Beckhoff IPC running Beckhoff RT Linux and Docker.

   c. Copy the edited `mqtt.xml` file to:
   ```
   C:\Program Files (x86)\Beckhoff\TwinCAT\3.1\Target\Routes\
   ```

   d. Restart the **TwinCAT System Service on Windows** (right-click the TwinCAT icon in the system tray → Config).

   e. The containerized TwinCAT runtime should appear as an available target system in TwinCAT Engineering. In the default sample configuration, look for the target that uses AMS Net ID `15.15.15.3.1.1`.

![](docs/choose-target-system.png)

**Troubleshooting:** If the target does not appear:
- Verify the Beckhoff IPC running Beckhoff RT Linux is reachable from the Windows engineering PC
- Verify the containers are running: `sudo docker compose ps` on the Beckhoff IPC running Beckhoff RT Linux
- Check container logs: `sudo docker compose logs`
- Use another MQTT client on Windows, such as MQTT Explorer, to check whether TwinCAT for Linux and the TwinCAT Engineering side have connected to the broker

## **5. Configure real-time Ethernet (Optional)**

**Note:** This step is only required if you plan to use EtherCAT or other real-time Ethernet protocols with TwinCAT.

Real-time Ethernet communication requires the `vfio-pci` driver for a PCI-based network device. Use the command line tool `TcRteInstall` to assign the `vfio-pci` driver to network devices of the IPC.

**Warning:** A network device bound to `vfio-pci` will no longer be available for standard Linux networking. Do not bind your primary network interface if you rely on it for remote access.

1. List available network devices for real-time Ethernet communication:

   ```bash
   sudo TcRteInstall -l
   ```

2. Assign the `vfio-pci` driver by passing the PCI device `Location` of the network interface you want to dedicate to TwinCAT:

   ```bash
   sudo TcRteInstall -b <PCI device Location>
   ```

   For example: `sudo TcRteInstall -b 0000:02:00.0`

   Choose a device that is not being used for your primary network connection to avoid losing connectivity to the host.

3. Verify the assignment:

   ```bash
   sudo TcRteInstall -l
   ```

   The output should now show `vfio-pci` in the `Driver` column for the device you configured.

4. For TwinCAT to detect the new configuration, restart the TwinCAT runtime container:

   ```bash
   sudo make restart-containers
   ```

   Or using docker compose directly:

   ```bash
   sudo docker compose -f tc31-xar-base/docker-compose.yaml restart tc31-xar-base
   ```

**Advanced:** By default, the container will probe all available PCI network devices bound to `vfio-pci`. You can control this behavior by setting the `PCI_DEVICES` environment variable in `tc31-xar-base/docker-compose.yaml`. See the comments above the `environment:` section in that file for details on setting `PCI_DEVICES` to `NONE` or an explicit list of PCI addresses.

### Sharing the host with a TwinCAT runtime on the host

If the TwinCAT runtime (`TcSystemServiceUm`) is also installed on the host, observe the following when containers use real-time Ethernet ports:

- **Exclude the container ports from the host runtime.** A `vfio-pci` port (more precisely its VFIO group) can be opened by only one process. Without restriction the host runtime probes all `vfio-pci` ports at start and the container fails with `EAL: Cannot open /dev/vfio/<n>: Device or resource busy`. Restrict the host runtime to the ports it should use (or `NONE`) with a systemd drop-in, and never list a port that a container uses:

  ```bash
  sudo mkdir -p /etc/systemd/system/TcSystemServiceUm.service.d
  sudo tee /etc/systemd/system/TcSystemServiceUm.service.d/override.conf <<'EOF'
  [Service]
  Environment=PCI_DEVICES=<PCI device Location of a port for the host, or NONE>
  EOF
  sudo systemctl daemon-reload && sudo systemctl restart TcSystemServiceUm
  ```

  Check with `sudo fuser -v /dev/vfio/<n>` that the group of the container's port is not held by the host. Alternatively disable the host runtime (`sudo systemctl disable --now TcSystemServiceUm`). Likewise give each container its own ports through `PCI_DEVICES` (`NONE` if it needs none), so containers do not claim the same port.
- **Hugepages are shared.** The containers use the hugepages of the host through the `/dev/hugepages` mount, and the pool is allocated on the host, not in the container. If no runtime allocates it, the container logs `EAL: Cannot get hugepage information.` and TwinCAT reports `Failed to connect to network adapter!`. Check with `grep -i huge /proc/meminfo` (`HugePages_Total` must be above 0) and allocate enough for all runtimes on the host (host runtime and containers), e.g. persistently:

  ```bash
  echo "vm.nr_hugepages=512" | sudo tee /etc/sysctl.d/90-hugepages.conf
  sudo sysctl --system
  ```

See the [reference setup](docs/reference-setup.md) for a worked example.

---

## Additional Commands

Each sample folder has its own `Makefile` (built on the shared `mk/common.mk`) with shortcuts for common Docker operations. The root `Makefile` delegates to a sample selected with `SAMPLE=<folder>` (default `tc31-xar-base`). Run `make help` to see the usage, or `make -C <sample> help` for a sample's targets:

```bash
make help
make list-samples
sudo make SAMPLE=tc31-xar-base build-image   # same as: sudo make -C tc31-xar-base build-image
```

Available targets:
- `build-image` — Build the TwinCAT container image
- `push-image` — Push the TwinCAT container image to a registry
- `run-containers` — Start containers using Docker Compose
- `restart-containers` — Restart containers
- `list-containers` — List all containers managed by Docker Compose
- `stop-and-remove-containers` — Stop and remove containers
- `container-logs` — Show logs for all containers
- `build-image-remote` — Build the image on the target defined in `apt-config.private/target.conf` (over SSH)
- `deploy-containers` — Copy the sample's compose files to the target and start the containers there
- `remote-container-logs` / `remote-stop-containers` — Follow logs / stop containers on the target

Remote build and deploy are described in [`apt-config/README.md`](apt-config/README.md).

Example:
```bash
sudo make build-image
sudo make run-containers
sudo make container-logs
```
