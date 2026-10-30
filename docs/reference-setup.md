# Reference setup

The samples were developed and tested on this hardware.

![Beckhoff C6030 Industrial PC](./c6030-main.webp)

## Hardware

| Item | Value |
|---|---|
| IPC | Beckhoff C6030-0080 |
| CPU | Intel Core i5, 11th generation |
| RAM | 2 x 8 GB |
| Storage | 80 GB SSD |
| OS | Beckhoff RT Linux |

## Network interfaces

Output of `sudo TcRteInstall -l`:

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

| Port (rear view) | Interface | PCI location | Driver | Use |
|---|---|---|---|---|
| LAN1 (top left) | `eno1` | `0000:00:1f.6` | `e1000e` | Host OS (Beckhoff RT Linux): maintenance / console / programming connection. Cannot be isolated from the host. Keep it disconnected from the network, except temporarily for those purposes. |
| LAN2 (top right) | `enp1s0` | `0000:01:00.0` | `vfio-pci` | Passed through to the Windows 11 VM. This is the port connected to the corporate network and is managed according to corporate IT rules. |
| LAN3 (bottom left) | `enp2s0` | `0000:02:00.0` | `vfio-pci` | Free to use, e.g. EtherCAT. Keep isolated from the corporate network. |
| LAN4 (bottom right) | `enp3s0` | `0000:03:00.0` | `vfio-pci` | Free to use, e.g. EtherCAT. Keep isolated from the corporate network. |

`[*]` in the `Override` column marks the NICs bound to `vfio-pci` (`enp1s0` for the VM, `enp2s0` and `enp3s0` for TwinCAT) with `sudo TcRteInstall -b <PCI device Location>`.

## Example: dedicated EtherCAT port for `tc31-xar-motion`

```bash
sudo PCI_DEVICES=0000:02:00.0 make SAMPLE=tc31-xar-motion restart-containers
```

Each real-time port can only be used by one runtime. If the TwinCAT runtime is also installed on the host, restrict it with `PCI_DEVICES` (e.g. `0000:03:00.0`, LAN4, or `NONE`) so it does not claim `0000:02:00.0`, and make sure hugepages are allocated on the host. See [the main README](../README.md#5-configure-real-time-ethernet-optional) and the [`tc31-xar-motion` README](../tc31-xar-motion/README.md#4-real-time-ethernet-ethercat).
