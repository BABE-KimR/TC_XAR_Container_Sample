# Portainer and replacing containers

## Install a Portainer server

[Portainer](https://www.portainer.io/) Community Edition is a web UI to inspect, start, stop and replace the containers on the IPC. Run it on the IPC next to the other samples:

```bash
sudo docker volume create portainer_data
sudo docker run -d --name portainer --restart=always \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

Beckhoff RT Linux drops inbound traffic that is not explicitly allowed. Allow TCP port `9443` the same way as for MQTT (see the main README, step 2): add it to a file in `/etc/nftables.conf.d/`, for example `61-portainer.conf`:

```nft
table inet filter {
  chain input {
    tcp dport 9443 accept
  }
}
```

Then reload the firewall and restart Docker, because reloading nftables flushes Docker's rules:

```bash
sudo systemctl reload nftables
sudo systemctl restart docker
```

Open `https://<ip-of-the-ipc>:9443` and create the administrator user **within a few minutes** after the first start; otherwise Portainer locks the setup and you have to restart it (`sudo docker restart portainer`). The browser warns about the self-signed certificate. Select the **local** environment.

Notes:

- Portainer has access to the Docker socket and therefore full control of the host. Only expose it in trusted networks and use a strong password.
- Portainer is not part of `container-network` and is not needed by the samples.
- Containers started with `make` / `docker compose` are shown in Portainer as *limited* stacks: you can start, stop, view logs and open a console, but not edit the stack. Manage their definition with the sample's compose file.

## Replace containers

A container is replaced by creating a new one from a (new) image or changed compose file. Data in the container is lost; keep settings in the compose file.

**With make (recommended)**, from the repository root on the IPC. A rebuild only retags the image, running containers keep the old one until they are recreated:

```bash
sudo make SAMPLE=<sample> build-image          # not for mosquitto-broker (uses a published image)
sudo make SAMPLE=<sample> restart-containers   # down + up: recreates the containers
```

For `mosquitto-broker` pull the latest published image first: `sudo docker compose -f mosquitto-broker/docker-compose.yaml pull`.

**From another machine**, using `apt-config.private/target.conf`: `make SAMPLE=<sample> build-image-remote` and then `make SAMPLE=<sample> deploy-containers`, which recreates changed containers on the target.

**With docker compose only**, after changing the compose file:

```bash
sudo docker compose -f <sample>/docker-compose.yaml up -d --force-recreate
```

**With Portainer:** open *Containers*, select the container and choose *Recreate* (tick *Pull latest image* for published images). A container that was started from the compose file keeps its settings. Do not use *Duplicate/Edit* for the samples; change the compose file instead, so settings like the fixed IP address, `PCI_DEVICES` and the AMS Net ID stay reproducible.

**Remove a container manually** if a name is already in use (for example `The container name "/mosquitto" is already in use`):

```bash
sudo docker rm -f <container-name>
```

Only one TwinCAT runtime can use the real-time resources of a host: stop the running runtime (`sudo make SAMPLE=<sample> stop-and-remove-containers`) before you start another one.

Remove the old, unused images afterwards: `sudo docker image prune`.
