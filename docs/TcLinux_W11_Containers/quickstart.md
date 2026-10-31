# TwinCAT Linux RT with Windows 11 VM

## Docker, TwinCAT XAR Container, Mosquitto, and ADS-over-MQTT Setup
This procedure configures Docker containers on Beckhoff RT Linux while preserving a pre-installed Windows 11 VM with GPU passthrough.

> **Important:** The pre-installed Windows VM depends on its validated QEMU environment and custom GPU ROM configuration. Follow the package-management and AppArmor steps in this guide before proceeding with Docker or container deployment.

> **Credential security:** Replace all credential placeholders locally. Do not include real passwords, tokens, or secrets in documentation, Git repositories, shell history, or shared chat.

---

## 1. Protect QEMU packages used by the Windows VM
Perform this step immediately after restoring the original IPC image and **before** changing APT repositories, running package updates, or installing Docker.

Create a script that detects all installed `qemu-*` packages, creates a backup, holds those packages, and pins their installed versions.

```bash
cat > ~/protect-windowsvm-qemu.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run this script with sudo."
    exit 1
fi

PREF_FILE="/etc/apt/preferences.d/90-windowsvm-qemu"
BACKUP_DIR="/root/windowsvm-qemu-protection-$(date +%Y%m%d-%H%M%S)"

mapfile -t QEMU_PACKAGES < <(
    dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' 'qemu-*' 2>/dev/null \
    | awk '$2 ~ /^ii/ {print $1 "\t" $3}'
)

if (( ${#QEMU_PACKAGES[@]} == 0 )); then
    echo "Error: No installed QEMU packages were found."
    exit 1
fi

mkdir -p "$BACKUP_DIR"

cp -a /var/lib/dpkg/status "$BACKUP_DIR/dpkg-status"
apt-mark showhold > "$BACKUP_DIR/apt-holds-before.txt" || true

{
    echo "# Generated $(date -Is)"
    echo "# Keeps the QEMU package versions installed with the Windows VM image."
    echo

    for item in "${QEMU_PACKAGES[@]}"; do
        package="${item%%$'\t'*}"
        version="${item#*$'\t'}"

        cat <<EOL
Package: $package
Pin: version $version
Pin-Priority: 1001

EOL
    done
} > "$PREF_FILE"

for item in "${QEMU_PACKAGES[@]}"; do
    package="${item%%$'\t'*}"
    apt-mark hold "$package"
done

echo
echo "QEMU packages are now held and pinned."
echo "Backup saved in: $BACKUP_DIR"

echo
echo "--- Protected QEMU packages ---"
printf '%s\n' "${QEMU_PACKAGES[@]}"

echo
echo "--- APT holds ---"
apt-mark showhold | grep '^qemu' || true

echo
echo "--- APT pin file ---"
cat "$PREF_FILE"
EOF

```
Make the script executable and run it:

```bash
chmod +x ~/protect-windowsvm-qemu.sh
sudo ~/protect-windowsvm-qemu.sh

```
Verify that the packages are held and inspect the candidate version for the main QEMU package:

```bash
apt-mark showhold | grep '^qemu'
apt-cache policy qemu-system-x86

```
Record the QEMU package names and versions in the IPC commissioning record.

---

## 2. Apply safe APT operating rules

### Safe: refresh package metadata
This command refreshes APT package metadata only. It does not install, remove, or upgrade packages:

```bash
sudo apt update

```

### Recommended installation pattern
Use `--no-upgrade` when installing required software:

```bash
sudo apt install --yes --no-upgrade <package-name>

```

### Do not perform routine system upgrades
Do not use these commands during normal Docker, Mosquitto, or TwinCAT XAR setup:

```bash
sudo apt upgrade
sudo apt full-upgrade
sudo apt-get dist-upgrade

```
The QEMU package hold and version pin prevent normal APT selection of newer detected QEMU packages. However, a broad system update can still modify other dependencies relevant to the VM.

If a broader update is unavoidable, simulate it first:

```bash
sudo apt upgrade --simulate

```
Review the proposed package changes. Do not proceed if the transaction changes QEMU, virtualization, kernel, VFIO, libvirt, or other VM-relevant packages unless the VM/image owner has validated the change.

---

## 3. Preserve the Windows VM pipeline repository
Do not delete, overwrite, or permanently disable the existing pipeline repository file:

```text
/etc/apt/sources.list.d/pipelines.list

```
Back it up before making any source-list changes:

```bash
sudo cp -a \
  /etc/apt/sources.list.d/pipelines.list \
  /root/pipelines.list.original

```
The pipeline source may be associated with the installed Windows VM environment. Retain it unless an approved VM maintenance procedure explicitly requires a change.

---

## 4. Configure myBeckhoff credentials for APT
APT automatically reads authentication files located in `/etc/apt/auth.conf.d/` when accessing package repositories.[^1]

Create the Beckhoff APT authentication file:

```bash
sudo nano /etc/apt/auth.conf.d/bhf.conf

```
Add the myBeckhoff credentials for both Beckhoff package endpoints:

```text
machine deb.beckhoff.com login <myBeckhoff-email> password <myBeckhoff-password>
machine deb-mirror.beckhoff.com login <myBeckhoff-email> password <myBeckhoff-password>

```
Restrict access to root:

```bash
sudo chmod 600 /etc/apt/auth.conf.d/bhf.conf

```
Verify the permission mode:

```bash
sudo ls -l /etc/apt/auth.conf.d/bhf.conf

```
Expected mode:

```text
-rw------- 1 root root ...

```

---

## 5. Configure the Beckhoff RT Linux repository
Create a script that updates the Beckhoff RT Linux repository definition while preserving the Windows VM pipeline source.

```bash
cat > ~/fix-apt-repositories.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

BHF_LIST="/etc/apt/sources.list.d/bhf.list"
PIPELINES_LIST="/etc/apt/sources.list.d/pipelines.list"
KEYRING="/usr/share/keyrings/bhf.asc"
BACKUP_DIR="/root/apt-sources-backup-$(date +%Y%m%d-%H%M%S)"

if [[ $EUID -ne 0 ]]; then
    echo "Run this script with sudo."
    exit 1
fi

if [[ ! -f "$KEYRING" ]]; then
    echo "Error: Beckhoff keyring not found: $KEYRING"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

if [[ -f "$BHF_LIST" ]]; then
    cp -a "$BHF_LIST" "$BACKUP_DIR/"
fi

if [[ -f "$PIPELINES_LIST" ]]; then
    cp -a "$PIPELINES_LIST" "$BACKUP_DIR/"
fi

cat > "$BHF_LIST" <<EOL
# Beckhoff RT Linux testing repository
deb [signed-by=$KEYRING] https://deb.beckhoff.com/debian trixie-testing main
EOL

echo "Repository file updated."
echo "Backup saved in: $BACKUP_DIR"
echo "The existing pipelines.list file was preserved."
echo

apt update
EOF

```
Make the script executable:

```bash
chmod +x ~/fix-apt-repositories.sh

```
Run the script:

```bash
sudo ~/fix-apt-repositories.sh

```

---

## 6. Install Git and clone the TwinCAT XAR container sample
Install Git without upgrading existing packages:

```bash
sudo apt install --yes --no-upgrade git

```
Clone the sample repository:

```bash
git clone https://github.com/Beckhoff/TC_XAR_Container_Sample.git
cd TC_XAR_Container_Sample

```
The repository includes:

```text
Makefile
docker-compose.yaml
mqtt.xml
simple-mosquitto.conf
tc31-xar-base/

```

---

## 7. Install Docker and required tools
Install Docker, Docker Compose, Make, and the TwinCAT system configuration utility:

```bash
sudo apt install --yes --no-upgrade \
  docker.io docker-compose make tcsysconf

```

| Package | Purpose |
| --- | --- |
| docker.io | Docker engine for building and running containers |
| docker-compose | Compose implementation used by the sample repository |
| make | Executes Makefile targets |
| tcsysconf | TwinCAT system configuration utility |

> `--no-upgrade` prevents upgrades of already installed packages requested by the installation. It does not prevent APT from installing missing dependencies. In this setup, Docker installation can install AppArmor; this activates libvirt guest confinement and requires the next section.

Verify that Docker is running:

```bash
sudo systemctl status docker

```
Expected relevant status:

```text
Active: active (running)

```
Verify Docker end-to-end:

```bash
sudo docker run hello-world

```
This confirms that the Docker client can contact the local daemon, pull an image, create a container, run it, and return the result.

---

## 8. Restore and validate Windows VM access after Docker installation

> **Required for a **`vm-installer --passthru`** Windows VM**

>

> Docker installation may install and enable AppArmor. Libvirt system guests run QEMU under dynamically generated AppArmor profiles. A Windows VM that uses a custom GPU ROM requires explicit read access to that ROM file.

Do not disable AppArmor, use complain mode, remove the GPU passthrough device, or remove the ROM reference from the VM definition.

### 8.1 Identify an AppArmor ROM-access denial
A failed VM start may report a misleading QEMU error similar to:

```text
failed to find romfile

```
Check for an AppArmor denial:

```bash
sudo journalctl -b -k --no-pager | grep -i 'apparmor.*DENIED'

```
A relevant denial resembles:

```text
apparmor="DENIED" operation="open"
profile="libvirt-<VM-UUID>"
name="/var/lib/libvirt/roms/windowsvm_00:02.0.rom"
comm="qemu-system-x86"
requested_mask="r" denied_mask="r"

```
This means that QEMU is blocked by AppArmor from reading the custom GPU ROM, even if the file exists and normal Linux permissions are correct.

### 8.2 Back up and inspect the local libvirt AppArmor override
Create the override directory:

```bash
sudo install -d -m 0755 /etc/apparmor.d/local/abstractions

```
Back up any existing override:

```bash
sudo test -f /etc/apparmor.d/local/abstractions/libvirt-qemu && \
  sudo cp -a \
    /etc/apparmor.d/local/abstractions/libvirt-qemu \
    /etc/apparmor.d/local/abstractions/libvirt-qemu.before-windowsvm-rom

```
Inspect the existing override file:

```bash
sudo cat /etc/apparmor.d/local/abstractions/libvirt-qemu 2>/dev/null || true

```

### 8.3 Allow read-only access to the custom GPU ROM
Add a narrow read-only rule for the exact ROM file:

```bash
echo '/var/lib/libvirt/roms/windowsvm_00:02.0.rom r,' | \
  sudo tee -a /etc/apparmor.d/local/abstractions/libvirt-qemu

```
The rule is:

```text
/var/lib/libvirt/roms/windowsvm_00:02.0.rom r,

```
It allows QEMU to read only this specific file. It does not grant write access and does not allow access to arbitrary ROM files.

Verify that the base libvirt QEMU abstraction includes the local override:

```bash
sudo grep -nE 'local/abstractions/libvirt-qemu|include.*local' \
  /etc/apparmor.d/abstractions/libvirt-qemu

```
Libvirt uses dynamically generated AppArmor profiles for system guests. Its static `libvirt-qemu` policy supports local overrides; this is preferable to editing generated per-VM AppArmor policy files directly.[^2]

### 8.4 Reload AppArmor and start the Windows VM
Reload AppArmor:

```bash
sudo systemctl reload apparmor

```
Start the Windows VM:

```bash
sudo virsh start windowsvm

```
Verify the VM state:

```bash
sudo virsh list --all

```
Expected result:

```text
 Id   Name        State
---------------------------
 1    windowsvm   running

```
Confirm that no new GPU-ROM denial was logged:

```bash
sudo journalctl -b -k --no-pager | \
  grep -F 'windowsvm_00:02.0.rom' || true

```

### 8.5 Troubleshooting
If AppArmor cannot be reloaded or the VM remains blocked, collect the following information before making broader changes:

```bash
sudo systemctl status apparmor --no-pager -l

sudo grep -nE 'include.*local|libvirt-qemu' \
  /etc/apparmor.d/abstractions/libvirt-qemu

sudo sed -n '1,220p' \
  /etc/apparmor.d/local/abstractions/libvirt-qemu

sudo journalctl -b -k --no-pager | tail -n 100

```

---

## 9. Configure credentials for the container image build
The sample image build uses a separate BuildKit secret file.

Edit the file:

```bash
sudo nano ./tc31-xar-base/apt-config/bhf.conf

```
Use the same myBeckhoff credential format:

```text
machine deb.beckhoff.com login <myBeckhoff-email> password <myBeckhoff-password>
machine deb-mirror.beckhoff.com login <myBeckhoff-email> password <myBeckhoff-password>

```
Do not commit this populated file to Git.

---

## 10. Build the TwinCAT XAR base image
Build the local image:

```bash
sudo make build-image

```
This invokes a Docker BuildKit command equivalent to:

```bash
docker build --no-cache \
  --secret id=apt,src=./tc31-xar-base/apt-config/bhf.conf \
  --network host \
  -t tc31-xar-base:latest \
  -f ./tc31-xar-base/Dockerfile \
  ./tc31-xar-base

```
The build:

1. Uses `debian:trixie-slim` as the base image.
2. Temporarily mounts `bhf.conf` as a BuildKit secret.
3. Retrieves the Beckhoff package signing key.
4. Configures the required package feeds.
5. Installs the required TwinCAT XAR packages.
6. Copies the sample configuration and entrypoint files.
7. Creates the local image:

```text
tc31-xar-base:latest

```

---

## 11. Configure the firewall for MQTT
Create an nftables include file:

```bash
sudo nano /etc/nftables.conf.d/60-mosquitto-container.conf

```
Add the MQTT rules:

```nft
table inet filter {
  chain input {
    # Allow DHCP requests from the Windows VM on the libvirt bridge.
    # Required for libvirt dnsmasq to assign an address to the VM.
    iifname "br200" udp sport 68 udp dport 67 accept

    # Allow incoming MQTT client connections.
    tcp dport 1883 accept
  }
}

table inet filter {
  chain forward {
    type filter hook forward priority 0; policy drop;

    # Allow forwarded MQTT traffic.
    tcp sport 1883 accept
    tcp dport 1883 accept
  }
}

```

> **Windows VM DHCP requirement:** The pre-installed Windows VM uses the libvirt bridge `br200`. Libvirt provides the VM address through its local DHCP service (`dnsmasq`), which listens on UDP port `67` on the RT Linux host. If the firewall input policy is restrictive, DHCP requests from `br200` must be allowed. Otherwise, the VM may fail to obtain or renew its address and use a `169.254.x.x` APIPA address instead.
Apply the firewall configuration:

```bash
sudo systemctl reload nftables

```
Display the active ruleset:

```bash
sudo nft list ruleset

```

Verify that the DHCP rule is active:

```bash
sudo nft list chain inet filter input

```

Expected relevant rules:

```text
iifname "br200" udp sport 68 udp dport 67 accept
tcp dport 1883 accept
```
Restart Docker after reloading nftables:

```bash
sudo systemctl restart docker

```

After starting or restarting the Windows VM, verify that libvirt issued a DHCP lease:

```bash
sudo virsh net-dhcp-leases br200

```

The VM should receive `10.0.200.10` in this setup. Do not rely on a specific MAC address in the output; it is installation-specific.
Reloading nftables removes Docker-created network rules. Restarting Docker lets Docker recreate those rules.[^3]

The port-based rules allow the Windows VM to connect to the broker through the `br200` address, provided the VM has network access to that bridge. For a more restrictive configuration, the rule can be limited to `br200` and the VM subnet:

```nft
iifname "br200" ip saddr 10.0.200.0/24 tcp dport 1883 accept

```

---

## 12. Start the TwinCAT XAR and Mosquitto containers
Start the Compose application:

```bash
sudo make run-containers

```
This runs:

```bash
docker compose up -d

```
The operation:

- pulls the Mosquitto image;
- creates the `container-network` Docker network;
- starts the `mosquitto` MQTT broker container;
- starts the `tc31-xar-base` TwinCAT XAR container.
Verify the container status:

```bash
sudo make list-containers

```
This executes:

```bash
docker compose ps -a

```
Expected relevant status:

| Container | Image | Expected status | Network exposure |
| --- | --- | --- | --- |
| mosquitto | eclipse-mosquitto:latest | healthy | Host TCP port 1883 |
| tc31-xar-base | tc31-xar-base:latest | healthy | TwinCAT-related container ports |

---

## 13. Identify the Windows VM bridge address
Display host network interfaces:

```bash
ip addr

```
In this setup, the Windows VM uses the `br200` bridge:

```text
br200: 10.0.200.1/24

```
Use this bridge address as the MQTT broker endpoint for the Windows VM:

```text
10.0.200.1

```

> The IP address is environment-specific. If `br200` has another address in a different installation, use that address in the MQTT configuration and test commands.

---

## 14. Configure ADS-over-MQTT
Edit the MQTT configuration file in the sample repository:

```bash
sudo nano mqtt.xml

```
Configure the broker endpoint and topic:

```xml
<?xml version="1.0" encoding="ISO-8859-1"?>
<TcConfig xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.beckhoff.com/schemas/2015/12/TcConfig">
<RemoteConnections>
 <Mqtt Unidirectional="true">
  <Address Port="1883">10.0.200.1</Address>
  <Topic>AdsOverMqtt</Topic>
 </Mqtt>
</RemoteConnections>
</TcConfig>
```

| Setting | Value |
| --- | --- |
| MQTT broker address | 10.0.200.1 |
| MQTT broker port | 1883 |
| MQTT topic | AdsOverMqtt |
| MQTT mode | Unidirectional |

---

## 15. Copy `mqtt.xml` to the Windows 11 VM
Connect to the Windows 11 VM using SSH.

Create the TwinCAT routes directory:

```cmd
mkdir "C:\Program Files (x86)\Beckhoff\TwinCAT\3.1\Target\Routes"

```
Copy the MQTT configuration from the RT Linux host to the Windows VM:

```cmd
scp Administrator@192.168.68.69:~/TC_XAR_Container_Sample/mqtt.xml "C:\Program Files (x86)\Beckhoff\TwinCAT\3.1\Target\Routes\mqtt.xml"

```
The file is copied to:

```text
C:\Program Files (x86)\Beckhoff\TwinCAT\3.1\Target\Routes\mqtt.xml

```
The address `192.168.68.69` is the RT Linux host management/LAN address used for SCP access.

When connecting for the first time, confirm the RT Linux SSH host key when prompted.

---

## 16. Install Mosquitto command-line clients on Windows
If `winget` is not available, install Mosquitto directly from an elevated PowerShell session.

```powershell
$installer = "$env:TEMP\mosquitto-install.exe"

Invoke-WebRequest `
  -Uri "https://mosquitto.org/files/binary/win64/mosquitto-2.1.2-install-windows-x64.exe" `
  -OutFile $installer

Start-Process -FilePath $installer -ArgumentList "/S" -Wait

```
Open a new PowerShell or Command Prompt window and verify the installation:

```powershell
& "C:\Program Files\mosquitto\mosquitto_sub.exe" --help

```
The Mosquitto project provides supported Windows installer packages; the download page currently lists version 2.1.2 for Windows.[^4]

---

## 17. Test MQTT connectivity from the Windows VM
First, test basic TCP connectivity from the Windows 11 VM to the broker:

```powershell
Test-NetConnection 10.0.200.1 -Port 1883

```
Expected result:

```text
TcpTestSucceeded : True

```

---

## 18. Subscribe to the `AdsOverMqtt` topic
MQTT brokers do not generally maintain a browsable list of topics. A topic is verified by subscribing and receiving either a retained message or a newly published message.[^5]

On the Windows 11 VM, subscribe to the configured topic and display payload data as hexadecimal:

```powershell
& "C:\Program Files\mosquitto\mosquitto_sub.exe" `
  -h 10.0.200.1 `
  -p 1883 `
  -t AdsOverMqtt `
  -F "%t : %x"

```
Expected output when TwinCAT publishes ADS-over-MQTT data:

```text
AdsOverMqtt : <hexadecimal-payload>

```
Hexadecimal output is useful because ADS-over-MQTT payloads can contain binary data.

---

## 19. Perform an independent MQTT broker test
Use two terminals on the Windows VM.

### Terminal 1: Subscribe

```powershell
& "C:\Program Files\mosquitto\mosquitto_sub.exe" `
  -h 10.0.200.1 `
  -p 1883 `
  -t AdsOverMqtt `
  -v

```

### Terminal 2: Publish a temporary test message

```powershell
& "C:\Program Files\mosquitto\mosquitto_pub.exe" `
  -h 10.0.200.1 `
  -p 1883 `
  -t AdsOverMqtt `
  -m "mqtt-test"

```
Expected output in Terminal 1:

```text
AdsOverMqtt mqtt-test

```
This confirms:

- TCP connectivity between the Windows VM and the Mosquitto broker;
- firewall access to TCP port `1883`;
- successful MQTT publish and subscribe operations;
- access to the `AdsOverMqtt` topic.
After the basic MQTT test succeeds, receiving actual ADS-over-MQTT messages confirms that TwinCAT is publishing to the configured broker and topic.

---

## 20. Configure real-time Ethernet, hugepages, and host/container separation (optional)

Required only for EtherCAT or other real-time Ethernet. Source: root `README.md` step 5 and `docs/reference-setup.md`.

### 20.1 Select and bind the network adapters

```bash
sudo TcRteInstall -l                          # list NICs (Location, Driver, Override)
sudo TcRteInstall -b <PCI device Location>    # e.g. 0000:02:00.0
sudo TcRteInstall -l                          # Driver must now show vfio-pci
```

- A NIC bound to `vfio-pci` disappears from the Linux network stack (no `enpXs0` in the host or container). TwinCAT uses it by PCI address.
- Never bind the primary host connection (`eno1`, `0000:00:1f.6`, driver `e1000e`) and never the port passed through to the Windows VM unless intended. On this IPC: LAN2 `enp1s0` (`0000:01:00.0`) is the Windows VM/corporate port, LAN3 `enp2s0` (`0000:02:00.0`) and LAN4 `enp3s0` (`0000:03:00.0`) are free for EtherCAT and must stay isolated from the corporate network.
- Restart the runtime container afterwards: `sudo make restart-containers`.

### 20.2 Assign ports with `PCI_DEVICES`

`PCI_DEVICES` (in the sample's `docker-compose.yaml` environment, or on the command line) selects the ports a runtime uses: unset = probe all `vfio-pci` ports, `NONE` = none, or a space-separated list of PCI addresses.

```bash
sudo PCI_DEVICES=0000:02:00.0 make SAMPLE=tc31-xar-motion restart-containers
```

Give each container its own ports (`NONE` if it needs none). Only one TwinCAT runtime can use the real-time resources of a host, so the real-time cores must not be shared either.

### 20.3 IOMMU / VFIO groups

A `vfio-pci` port is opened per VFIO group (IOMMU group), and a group can be opened by only one process. If the log shows `EAL: Cannot open /dev/vfio/<n>: Device or resource busy` or `PCI_BUS: Requested device ... cannot be used`:

```bash
sudo fuser -v /dev/vfio/<n>                    # which process holds the group
ls /sys/kernel/iommu_groups/<n>/devices/       # other devices in the same group
sudo docker ps -a                              # stale containers
```

Typical causes: the host runtime `TcSystemServiceUm` (see 20.5), another container with `PCI_DEVICES` unset or the same port, or a stale container. Because the Windows VM also uses `vfio-pci` (LAN2), keep its IOMMU group separate from the TwinCAT ports.

### 20.4 Hugepages (on the host)

The containers use the host hugepages through the `/dev/hugepages` mount; the pool is allocated on the host, not in the container. Without it the container logs `EAL: Cannot get hugepage information.` and TwinCAT reports `Failed to connect to network adapter!`.

```bash
grep -i huge /proc/meminfo                     # HugePages_Total must be > 0
echo 512 | sudo tee /proc/sys/vm/nr_hugepages  # immediate
echo "vm.nr_hugepages=512" | sudo tee /etc/sysctl.d/90-hugepages.conf   # persistent
sudo sysctl --system
```

Allocate enough for all runtimes (host runtime and containers). Check that `/dev/hugepages` is a mounted `hugetlbfs`, then restart the container.

### 20.5 Dedicate ports with systemd when the host also runs TwinCAT

The host runtime `TcSystemServiceUm` probes all `vfio-pci` ports at start and would claim the container's port. Restrict it with a drop-in and never list a port used by a container:

```bash
sudo mkdir -p /etc/systemd/system/TcSystemServiceUm.service.d
sudo tee /etc/systemd/system/TcSystemServiceUm.service.d/override.conf <<'EOF'
[Service]
Environment=PCI_DEVICES=<PCI device Location of a port for the host, or NONE>
EOF
sudo systemctl daemon-reload && sudo systemctl restart TcSystemServiceUm
sudo fuser -v /dev/vfio/<n>                    # container port's group must not be held by the host
```

Alternatively disable the host runtime: `sudo systemctl disable --now TcSystemServiceUm`. If the unit name is unclear: `systemctl list-units --all | grep -i -E "tc|twincat"`.

[^1]: [Authenticate on the Beckhoff Package Server](https://infosys.beckhoff.com/content/1033/beckhoff_rt_linux/17350409995.html?id=8670635689681480738)
[^2]: [Libvirt – AppArmor isolation](https://ubuntu.com/server/docs/how-to/virtualisation/libvirt/)
[^3]: [Set firewall rules for MQTT connections](https://infosys.beckhoff.com/content/1033/beckhoff_rt_linux/19082094859.html?id=6242885682500101162)
[^4]: [Download | Eclipse Mosquitto](https://mosquitto.org/download/)
[^5]: [mosquitto_sub man page](https://mosquitto.org/man/mosquitto_sub-1.html)