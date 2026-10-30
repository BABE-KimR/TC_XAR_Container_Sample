# IOMMU, VFIO, PCI Addresses, and Direct Device Passthrough

## 1. What device passthrough is

**Direct device passthrough** gives a virtual machine (VM) direct use of a real physical device rather than an emulated or virtual device. Typical passthrough devices are GPUs, NICs, NVMe controllers, USB controllers, and accelerators.

```text
Virtual device path
Guest driver -> virtual device -> VM runtime / host driver -> physical device

Direct passthrough path
Guest native driver -> QEMU / VFIO -> IOMMU -> physical PCIe device
```

Passthrough can reduce latency and CPU overhead and gives the guest access to hardware-specific features. In exchange, the device is normally exclusive: the host cannot use it with its ordinary driver while the guest owns it.

---

## 2. PCI addresses

PCIe is the interconnect used by hardware such as GPUs, NICs, NVMe controllers, and USB controllers. Linux identifies each PCI function with a **BDF address**:

```text
0000:01:00.0
^^^^ ^^^ ^^ ^
 |    |  |  └─ function
 |    |  └──── slot/device
 |    └─────── PCI bus
 └──────────── PCI domain
```

The normal format is `domain:bus:slot.function`. It is a hardware identifier—not an IP address, TCP/UDP port, or Linux network-interface name.

One card can expose several PCI functions. For example, a graphics card can expose a graphics function at `0000:01:00.0` and an HDMI/DisplayPort audio function at `0000:01:00.1`.

Useful inspection commands:

```bash
lspci -nn
lspci -nnk -s 0000:01:00.0
```

`lspci -nnk` shows the device identity and the Linux kernel driver that currently owns it.

---

## 3. Why an IOMMU is needed

PCIe devices use **DMA** (Direct Memory Access) to read and write system memory efficiently. A device assigned to a VM must not be able to access arbitrary host memory or another VM's memory.

An **IOMMU** (Input-Output Memory Management Unit) is hardware that controls memory accesses made by I/O devices. It is conceptually similar to a CPU MMU, but for device DMA.

```text
CPU memory access:     virtual address -> CPU MMU -> physical memory
Device DMA access:     I/O address     -> IOMMU  -> physical memory
```

When a device is assigned to a VM, the VM runtime configures the IOMMU to allow DMA only to memory pages allocated to that VM:

```text
Assigned PCIe device
       |
       v
     IOMMU
       |
       +-- assigned VM memory      -> allowed
       +-- host memory             -> blocked
       +-- another VM's memory     -> blocked
```

On common x86 platforms, the feature is usually called **Intel VT-d** or **AMD-Vi / AMD IOMMU**. It must be enabled in platform firmware and by the operating system for secure passthrough.

---

## 4. IOMMU groups: the real isolation boundary

A PCI address identifies a device function, but the hardware cannot always isolate every function independently. PCIe topology, bridges, multi-function devices, and ACS capabilities can make several devices inseparable for DMA isolation.

Linux represents the smallest safely isolatable collection as an **IOMMU group**.

```text
Example: isolated group
IOMMU group 7
└── 0000:03:00.0  NIC

Potentially assignable by itself.
```

```text
Example: shared group
IOMMU group 12
├── 0000:04:00.0  Device A
└── 0000:04:00.1  Device B

The group is the assignment and security boundary, not Device A alone.
```

This is a hardware/topology property. Binding a device to `vfio-pci` does **not** itself prove that the device has an isolated IOMMU group.

Inspect the complete group before planning any assignment:

```bash
readlink -f /sys/bus/pci/devices/0000:01:00.0/iommu_group

for d in /sys/bus/pci/devices/0000:01:00.0/iommu_group/devices/*; do
  lspci -nnk -s "${d##*/}"
done
```

The Linux VFIO model uses the IOMMU group as its ownership unit. For the traditional VFIO group interface, a group must be viable before it can be assigned; devices in the group cannot remain partly owned by normal host drivers while another member is independently assigned.

---

## 5. What VFIO does

**VFIO** is the Linux kernel framework that exposes direct device access safely to userspace. `vfio-pci` is the driver typically used for PCIe device assignment.

```text
Ordinary host ownership
Physical NIC -> normal host driver -> host networking

Direct assignment
Physical NIC -> vfio-pci -> QEMU/libvirt -> guest-native driver
```

VFIO prevents the normal host driver from operating the assigned device and gives a VM runtime controlled access to PCI configuration, device regions, interrupts, and IOMMU-backed DMA mappings.

A device or VFIO group has one active owner at a time:

```text
VFIO device/group
       |
       +--> VM runtime / QEMU
       |
       +--> userspace workload (for example packet processing)

It cannot be actively owned by both at once.
```

A busy error such as the following indicates that another process has already opened the device or group:

```text
Could not open '/dev/vfio/<group>': Device or resource busy
```

Investigate with:

```bash
sudo fuser -v /dev/vfio/<group-number> || true
sudo lsof /dev/vfio/<group-number> 2>/dev/null || true
```

---

## 6. Simplified passthrough lifecycle

```text
1. Enable IOMMU in firmware and the OS.
2. Linux discovers PCI devices and IOMMU groups.
3. Confirm the target group is appropriate and unused.
4. Detach the target device from its normal host driver.
5. Bind it to vfio-pci using the supported platform procedure.
6. Configure the VM to reference the PCI device.
7. QEMU opens the VFIO group/device and configures IOMMU mappings.
8. The guest detects the physical device and loads its native driver.
```

During shutdown, QEMU releases its VFIO handles. The device may then be returned to a host driver, depending on the platform configuration.

---

## 7. Hardware-backed isolation: what it guarantees and what it does not

When IOMMU support is enabled and correctly configured, it is a real hardware feature that provides meaningful isolation for DMA and interrupt delivery. A passed-through device is limited to the memory mappings granted to its owner.

| Aspect | Meaning |
|---|---|
| DMA isolation | The device is restricted to approved memory mappings; unrelated host/VM memory is not normally accessible through DMA. |
| Ownership | VFIO prevents the ordinary host driver and another VFIO user from operating the same device/group concurrently. |
| Interrupts | Interrupt remapping can direct device interrupts safely to the intended owner. |
| Physical presence | The device remains physically attached to the host PCIe fabric; the host can enumerate it, but should not operate it through an ordinary driver while assigned. |
| Network reachability | A passed-through NIC remains connected to its external network. IOMMU does not restrict normal network traffic; guest firewall and network design do. |
| Absolute security guarantee | No. The result depends on correct firmware, platform topology/grouping, kernel configuration, device behavior, and the absence of hardware or firmware vulnerabilities. |

The strongest practical rule is: **only assign a clean, suitable IOMMU group, and give it one deliberate owner at a time.**

Do not use unsafe workarounds merely to force a non-isolated device into passthrough. A platform that cannot isolate the desired device cleanly requires a different device, slot, topology, or virtual-device design.

---

## 8. Containers and passthrough

Normal Docker containers use the host kernel and virtual Docker networking. Installing or starting Docker does not automatically grant a container access to a physical GPU, NIC, or VFIO group.

```text
Normal container
Container -> Docker virtual network -> host networking -> physical NIC

Device-enabled container
Container workload -> VFIO device/group -> physical PCIe device
```

A container can conflict with a VM only when it has deliberately been given the relevant device access, is privileged with appropriate device exposure, or uses another device-management layer that owns the VFIO group.

---

## 9. Example: three dedicated NICs and one host-managed NIC

The following `TcRteInstall -l` output is an example of a system where three dedicated Intel I226-IT NICs have been bound to `vfio-pci`, while the onboard I219-LM NIC remains under normal host-driver ownership:

```text
+-----+----------+-------------------+--------------+----------+----------+----------------------------------+------+
| No  | Name     | MAC               | Location     | Driver   | Override | Model                            | Link |
+-----+----------+-------------------+--------------+----------+----------+----------------------------------+------+
| 0   | enp3s0   | unknown           | 0000:03:00.0 | vfio-pci | [*]      | Ethernet Controller I226-IT      | un.. |
| 1   | enp2s0   | unknown           | 0000:02:00.0 | vfio-pci | [*]      | Ethernet Controller I226-IT      | un.. |
| 2   | enp1s0   | unknown           | 0000:01:00.0 | vfio-pci | [*]      | Ethernet Controller I226-IT      | un.. |
| 3   | eno1     | 00:01:05:a4:5f:56 | 0000:00:1f.6 | e1000e   | [-]      | Ethernet Connection (14) I219-LM | up   |
+-----+----------+-------------------+--------------+----------+----------+----------------------------------+------+
```

### What this output establishes

- `enp1s0`, `enp2s0`, and `enp3s0` are bound to `vfio-pci`.
- They are therefore reserved for a direct-device consumer such as a VM or a real-time/userspace workload, rather than ordinary host TCP/IP networking.
- `eno1` is still host-managed by the `e1000e` driver and has an active link.
- `unknown` MAC and an unavailable link state for the `vfio-pci` NICs are expected: a normal host network driver is no longer controlling those interfaces.

### What this output does *not* establish

It does **not**, by itself, prove that `enp1s0`, `enp2s0`, and `enp3s0` are each individually isolated IOMMU groups. `TcRteInstall -l` reports driver assignment; it does not display group membership.

To verify the required isolation, inspect every group separately:

```bash
for bdf in 0000:01:00.0 0000:02:00.0 0000:03:00.0; do
  echo "===== $bdf ====="
  group="$(basename "$(readlink -f "/sys/bus/pci/devices/$bdf/iommu_group")")"
  echo "IOMMU group: $group"
  for d in /sys/kernel/iommu_groups/"$group"/devices/*; do
    member="${d##*/}"
    lspci -nnk -s "$member"
  done
  echo
done
```

The NICs can be treated as independently assignable only if each target NIC is in a suitable group with no unrelated host-critical devices, and no other process already owns that VFIO group.

For Beckhoff RT Linux specifically, `TcRteInstall` is the documented tool for assigning a network interface intended for TwinCAT Real-Time Ethernet to `vfio-pci`. This documents the driver assignment step; IOMMU group membership remains a separate platform verification.[^2]

---

## 10. Pre-assignment checklist

1. Record the PCI address and vendor/device IDs.
2. Confirm IOMMU is enabled.
3. Inspect every member of the target IOMMU group.
4. Confirm the host does not depend on the device for management, display, storage, or production traffic.
5. Confirm no VM, container, or userspace workload already owns the group.
6. Bind the device using the supported platform procedure.
7. Back up the VM definition and plan rollback before making configuration changes.

---

## References

[^1]: [Linux Kernel documentation: VFIO - Virtual Function I/O](https://docs.kernel.org/driver-api/vfio.html)
[^2]: [Beckhoff Information System: Configure TwinCAT Real-Time Ethernet](https://infosys.beckhoff.com/content/1033/beckhoff_rt_linux/20793629195.html)
