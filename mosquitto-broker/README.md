# Mosquitto broker for ADS-over-MQTT

Standalone Eclipse Mosquitto MQTT broker for ADS-over-MQTT (topic `AdsOverMqtt`). TwinCAT runtimes (containers or other systems) and TwinCAT Engineering connect to it.

> **Required, and started separately.** All other samples (`tc31-xar-base`, `tc31-xar-motion`, `tc31-xar-motion-nci`, `tf2000-hmi-server`) need this broker and none of them starts one. Start this sample with its own `make` / compose, before the other samples, on the same host or on another system. A broker cannot be started from any other sample's compose file.

- Container `mosquitto`: 192.168.20.2 on `container-network` (192.168.20.0/24), configuration `simple-mosquitto.conf`, two listeners:
  - Port `1883`: plain MQTT, **anonymous**. Accepted by the host **only on the bridge adapter `br200`** (firewall rule below); containers on `container-network` reach it directly.
  - Port `8883`: MQTT over **TLS with user name and password, anonymous access is not allowed**. Accepted by the host on `eno1` and `br200`. It is **not used for ADS-over-MQTT** (that uses port 1883), only for other MQTT communication.
- No image to build: `eclipse-mosquitto:latest` is pulled from Docker Hub, no myBeckhoff credentials are needed.
- The anonymous port 1883 is unencrypted: it must not be reachable from other interfaces than `br200`.

**Migrating from an older `tc31-xar-base`:** earlier versions of `tc31-xar-base` started the broker themselves. If starting fails with `The container name "/mosquitto" is already in use`, remove the old broker container (it belongs to the `tc31-xar-base` compose project) and start this sample again:

```bash
sudo docker rm -f mosquitto
sudo make SAMPLE=mosquitto-broker run-containers
```

## Prerequisites

- A Linux host with Docker, Docker Compose and `make` (see the [main README](../README.md)).
- The TLS files and the password file for port 8883 in `mosquitto-broker/secure/` (below). The broker does not start without them. The folder is ignored by git and copied to the target by `deploy-containers`.
- The host firewall rules below.

### TLS certificate and user for port 8883

Run in the repository root. Replace `<host>` / `<ip>` with the name / IP address clients use to reach the IPC, and `<user>` with the MQTT user name:

```bash
mkdir -p mosquitto-broker/secure && cd mosquitto-broker/secure
openssl req -x509 -newkey rsa:4096 -nodes -days 3650 -keyout ca.key -out ca.crt -subj "/CN=mosquitto-ca"
openssl req -newkey rsa:4096 -nodes -keyout server.key -out server.csr -subj "/CN=<host>"
echo "subjectAltName=DNS:<host>,IP:<ip>" > san.ext
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 3650 -extfile san.ext -out server.crt
docker run --rm -it -v "$PWD:/secure" eclipse-mosquitto mosquitto_passwd -c /secure/passwd <user>
sudo chown 1883:1883 server.key server.crt ca.crt passwd && sudo chmod 600 server.key passwd
cd ../..
```

Keep `ca.key` safe and out of the target (the broker only needs `ca.crt`, `server.crt`, `server.key`, `passwd`); install `ca.crt` as trusted CA on the clients. Never commit anything from `secure/`. Add more users with `mosquitto_passwd /secure/passwd <user>` (without `-c`) and restart the broker.

### Firewall (nftables)

Beckhoff RT Linux drops inbound traffic that is not allowed. Create `/etc/nftables.conf.d/60-mosquitto-container.conf` (replaces the generic port 1883 rule of the main README, step 2):

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

Apply it and restart Docker (reloading nftables flushes Docker's rules):

```bash
sudo nft -c -f /etc/nftables.conf
sudo systemctl reload nftables
sudo systemctl restart docker
```

## Start the broker

From the repository root, on the host:

```bash
sudo make SAMPLE=mosquitto-broker run-containers
```

Or from another machine with SSH access to the target, using `apt-config.private/target.conf` (see [`apt-config/README.md`](../apt-config/README.md)). This copies `docker-compose.yaml`, `simple-mosquitto.conf` and the `secure` folder to the target and starts the broker there:

```bash
make SAMPLE=mosquitto-broker deploy-containers
```

The Docker network `container-network` is created automatically if it does not exist yet.

Check that the broker is running and healthy:

```bash
sudo make SAMPLE=mosquitto-broker list-containers
sudo make SAMPLE=mosquitto-broker container-logs
```

## Connect TwinCAT

Point the ADS-over-MQTT routes to the IP address of the host running this broker:

- ADS-over-MQTT always uses port `1883`, so the ADS-over-MQTT clients must be on `br200` (for example the Windows 11 VM) or on `container-network`.
- Port `8883` (TLS, trust `ca.crt`, user name / password) is for other MQTT clients on `eno1` or `br200`, not for ADS-over-MQTT.
- Windows engineering PC: `tc31-xar-base/mqtt.xml` template, see the [main README](../README.md), step 4.
- TwinCAT runtime containers on the same host: they reach the broker by the name `mosquitto` on `container-network` (see [`tc31-xar-motion`](../tc31-xar-motion/README.md)).

## Other commands

`restart-containers`, `stop-and-remove-containers`, `remote-container-logs` and `remote-stop-containers` work as for the other samples: `sudo make SAMPLE=mosquitto-broker <target>`.
