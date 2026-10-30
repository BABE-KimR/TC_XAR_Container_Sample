# TF2000 TwinCAT 3 HMI Server container

> **⚠️ NOT WORKING:** This sample is work in progress and does not run successfully yet. Do not use it in production.

Container image and Compose setup for the [TF2000 | TwinCAT 3 HMI Server](https://infosys.beckhoff.com/content/1033/tf2000_tc3_hmi_server/19752824203.html) on a Beckhoff IPC running Beckhoff RT Linux. The container installs the Debian package `tf2000-hmi-server` from the Beckhoff package server and runs the server instead of the `TcHmiSrv.service` systemd unit, initializing the server instance (`TcHmiSrv --initialize`) on first start.

The container joins the Docker network `container-network` (192.168.20.0/24) that is shared with the other TwinCAT container samples, so it reaches the other TwinCAT containers locally:

- `tf2000-hmi-server`: 192.168.20.10, AMS Net ID `15.15.15.10.1.1`
- ADS traffic to the other containers (for example `tc31-xar-base`, AMS Net ID `15.15.15.3.1.1`) goes through the `mosquitto` broker (ADS-over-MQTT, topic `AdsOverMqtt`) via `TwinCAT/StaticRoutes.xml`.

The sample can be deployed independently of the other samples. It only needs a reachable MQTT broker named `mosquitto` on `container-network`; the [`mosquitto-broker`](../mosquitto-broker/README.md) sample provides one and must be started separately. The network is created automatically if it does not exist yet.

## Prerequisites

- Beckhoff IPC with Beckhoff RT Linux, Docker and `make` as described in the [main README](../README.md).
- A running `mosquitto` container on `container-network` (start the [`mosquitto-broker`](../mosquitto-broker/README.md) sample, or any broker with that name and network).
- A private copy of the apt configuration with your myBeckhoff credentials, see [`apt-config/README.md`](../apt-config/README.md):

  ```bash
  cp -r apt-config apt-config.private
  nano apt-config.private/bhf.conf
  nano apt-config.private/hmi.env   # set HMI_PASSWORD, the password of the HMI server
  ```

  `hmi.env` stays in the gitignored private folder; never commit a real password. `make` passes it to Docker Compose as `--env-file`. For `deploy-containers` it is copied to the target as `.env` with permissions `600`. If you call `docker compose` directly, export `HMI_PASSWORD` or place a `.env` file next to `docker-compose.yaml` (also gitignored).

## 1. Build the image

From the repository root, on the IPC:

```bash
sudo make SAMPLE=tf2000-hmi-server build-image
```

Or from a Windows PC / any machine with SSH access to the IPC, using `apt-config.private/target.conf` (see [`apt-config/README.md`](../apt-config/README.md), and [Windows with WSL2](../docs/windows-wsl2-build.md)):

```bash
make SAMPLE=tf2000-hmi-server build-image-remote
```

## 2. Open the firewall port

Only the HTTPS port `2020` is published and exposed; the HTTP endpoint on `2010` is local to the container (`--endpoint=http://127.0.0.1:2010`). Allow `2020` on the IPC, as described in the [TF2000 documentation](https://infosys.beckhoff.com/content/1033/tf2000_tc3_hmi_server/19752826507.html). Because the port is published by Docker, the forward chain needs a rule as well. Create `/etc/nftables.conf.d/20-hmi.conf`:

```nft
table inet filter {
  chain input {
    # accept TcHmi
    tcp dport 2020 accept
  }
  chain forward {
    type filter hook forward priority 0; policy drop;
    tcp dport 2020 accept
    tcp sport 2020 accept
  }
}
```

Then reload nftables and restart Docker, because the reload flushes Docker's own rules, and verify:

```bash
sudo systemctl reload nftables
sudo systemctl restart docker
sudo nft list ruleset
```

The HMI server also needs the rule for traffic inside `container-network` (`ip saddr 192.168.20.0/24 ip daddr 192.168.20.0/24 accept`) to reach the broker; it is part of the firewall file of the [`mosquitto-broker`](../mosquitto-broker/README.md) sample.

If the `mosquitto-broker` firewall file already declares the `forward` chain with `type filter hook forward ...`, nftables merges rules into the existing chain; keep that declaration in only one of the files if you see a "chain already defined" error.

## 3. Start the container

On the IPC:

```bash
sudo make SAMPLE=tf2000-hmi-server run-containers
```

Or deploy remotely (copies `docker-compose.yaml` to the target and starts it there):

```bash
make SAMPLE=tf2000-hmi-server deploy-containers
```

On the first start the entrypoint initializes the server instance (`TcHmiSrv --initialize` with `HMI_INIT_ARGS`, see below). Check that the container runs and is healthy:

```bash
sudo make SAMPLE=tf2000-hmi-server list-containers
sudo make SAMPLE=tf2000-hmi-server container-logs
```

The HMI server is then available at `https://<ipc-address>:2020`. Use this address as the target in TwinCAT HMI Engineering.

## Additional settings

- **MQTT broker access (firewall):** the container reaches the broker `mosquitto` inside Docker's `container-network`, so no extra host rule is needed when it runs on the same IPC. If the broker runs on another host, replace `mosquitto` in `TwinCAT/StaticRoutes.xml` with its address, rebuild the image, and allow outgoing TCP `1883` on that host as described in the [main README](../README.md) (step 2).
- **Host firewall scope:** only TCP `2020` is opened. Do not open `2010`; it is bound to `127.0.0.1` inside the container and is not published. Restrict the rule to your engineering network if required, for example `ip saddr 192.168.1.0/24 tcp dport 2020 accept` in the `input` chain.
- **Ports below 1024:** the container runs as root, so no `CAP_NET_BIND_SERVICE` configuration (as needed for the `TcHmiSrv` systemd service) is required. To change the HTTPS port, set the matching endpoint in `HMI_INIT_ARGS`, the `ports:` mapping, and the firewall rule.
- **Extension files and executables:** the `ReadWritePaths` / `ExecPaths` whitelisting of the systemd service does not apply in the container. Make additional paths available with a `volumes:` entry in `docker-compose.yaml`.
- **Windows engineering PC:** TwinCAT HMI Engineering connects to the server on `https://<ipc-address>:2020`; no `mqtt.xml` is required for this sample. You only need it (see the [main README](../README.md), step 4) to reach the TwinCAT runtime containers from TwinCAT Engineering.
- **Docker restart after firewall changes:** reloading nftables flushes Docker's own rules, so always run `sudo systemctl restart docker` afterwards and then start the containers again.

## Configuration

- `AMS_NETID` in `docker-compose.yaml`: AMS Net ID of this container. It must be unique among all TwinCAT containers.
- `HMI_PASSWORD`: password for `TcHmiSrv --initialize --password=<password>`, required on the first start. Set it in `apt-config.private/hmi.env` (see Prerequisites); it is not stored in the image or in `docker-compose.yaml`.
- `HMI_INIT_ARGS` in `docker-compose.yaml`: further arguments passed to `TcHmiSrv --initialize` on the first start (when `/var/lib/tchmisrv/service` is empty). Default: `--endpoint=http://127.0.0.1:2010`. Add further parameters from `TcHmiSrv --help`, for example `--name=MyProject`.
- `HMI_SERVER_CMD` (optional environment variable): overrides the command that starts the HMI server. By default `entrypoint.sh` reads `ExecStart` (and `WorkingDirectory` / `Environment`) from the `TcHmiSrv.service` unit installed by the package.
- The named volume `hmi-server-data` persists the server instance and deployed projects in `/var/lib/tchmisrv` (server >= 14.5.73). To re-initialize, remove the container and the volume: `sudo docker compose down -v`.
- The fixed IP `192.168.20.10` must be free on `container-network`; change it in `docker-compose.yaml` if you add other containers.
- To reach a TwinCAT runtime from the HMI server, address it by its AMS Net ID (for example `15.15.15.3.1.1`) in the server's ADS configuration. The route is provided by the MQTT connection; no extra route entry is needed in this sample.

## Useful commands

The systemd commands of the [TF2000 documentation](https://infosys.beckhoff.com/content/1033/tf2000_tc3_hmi_server/20917077771.html) map to Docker as follows (run from the repository root on the IPC, prefix with `sudo`):

| Documented command | In this sample |
|---|---|
| `TcHmiSrv --help` | `docker exec tf2000-hmi-server TcHmiSrv --help` |
| `systemctl start/stop/restart TcHmiSrv.service` | `make SAMPLE=tf2000-hmi-server run-containers` / `stop-and-remove-containers` / `restart-containers`, or `docker compose -f tf2000-hmi-server/docker-compose.yaml start/stop/restart` |
| `systemctl enable/disable TcHmiSrv.service` | Container restart policy `restart: unless-stopped` in `docker-compose.yaml` (autostart); `make ... stop-and-remove-containers` disables it |
| `TcHmiSrv --initialize ...` | Runs automatically on the first start with `HMI_INIT_ARGS` |
| Factory reset, all services | `docker exec tf2000-hmi-server TcHmiSrv --factoryReset --serviceDir=/var/lib/tchmisrv/service` |
| Factory reset, one service | `docker exec tf2000-hmi-server TcHmiSrv --factoryReset --serviceDir=/var/lib/tchmisrv/service/<ServiceName>` |

To reinitialize the server from scratch, stop the container, remove the volume so the first-start initialization runs again, and start it:

```bash
sudo docker compose -f tf2000-hmi-server/docker-compose.yaml down -v
sudo make SAMPLE=tf2000-hmi-server run-containers
```

For servers older than 14.5.73 the service folder is `/etc/TwinCAT/Functions/TF2000-HMI-Server/service` instead of `/var/lib/tchmisrv/service`; adjust the volume mount in `docker-compose.yaml` and the `data_dir` check in `entrypoint.sh` accordingly.

## Troubleshooting

- **Initialization fails in the logs:** check that `HMI_PASSWORD` is set (`HMI_PASSWORD is not set` in the log) and that it meets the server's password requirements. Further required parameters can be added to `HMI_INIT_ARGS`; see the [documented command](https://infosys.beckhoff.com/content/1033/tf2000_tc3_hmi_server/19752826507.html).
- **Container restarts, logs say `TcHmiSrv.service not found`:** the package layout may differ from the expected one. Set `HMI_SERVER_CMD` in `docker-compose.yaml`, or inspect the image with `docker run --rm --entrypoint sh tf2000-hmi-server -c "dpkg -L tf2000-hmi-server"`.
- **`network container-network declared as external, but could not be found`:** run through `make` (creates the network), or create it manually with the same settings as in `tc31-xar-base/docker-compose.yaml`.
- **Health check unhealthy:** the check requests `http://127.0.0.1:2010/` inside the container. Adjust it in `docker-compose.yaml` if you changed the local endpoint.
- **Windows engineering PC cannot reach the server:** check the firewall step above and that `2020` is published (`docker compose ps`).
