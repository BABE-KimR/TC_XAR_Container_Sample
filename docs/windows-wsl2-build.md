# Building the container images on Windows with WSL2 (without Docker Desktop)

This guide installs the open-source Docker Engine (`docker.io`) inside a WSL2 Debian distribution, so you can build the images from this repository on a Windows PC without Docker Desktop or its GUI. Check your own organization's licensing requirements; Docker Engine from the Debian packages is distributed under the Apache 2.0 license.

The images are built only. Running the TwinCAT runtime needs a Beckhoff IPC with Beckhoff RT Linux, so the last step transfers the image to the IPC.

## 1. Install WSL2 with Debian

In an **administrator PowerShell** on Windows:

```powershell
wsl --install -d Debian
```

Reboot if requested, then finish the Debian first-start (create a Linux user and password). Verify the distribution runs as WSL version 2:

```powershell
wsl -l -v
```

## 2. Enable systemd in the distribution

Inside the Debian shell:

```bash
sudo tee /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true
EOF
```

Back in PowerShell, restart the distribution:

```powershell
wsl --shutdown
```

## 3. Install Docker Engine, Buildx and make

Open Debian again and run:

```bash
sudo apt update
sudo apt install --yes docker.io docker-buildx make git
sudo usermod -aG docker "$USER"
```

Close and reopen the Debian shell so the group change takes effect, then verify:

```bash
docker version
docker buildx version
```

The build uses BuildKit features (`--secret`, `--build-context`), which require `docker-buildx`.

## 4. Clone the repository inside WSL

Work in the Linux filesystem (for example `~`), **not** under `/mnt/c`. This is faster and avoids line-ending and permission problems. The repository's `.gitattributes` enforces LF line endings, which the scripts in the images require.

```bash
cd ~
git clone <repository-url>
cd <repository-folder>
```

## 5. Create the private apt configuration

Copy the template and add your myBeckhoff credentials. Never edit `apt-config` itself and never commit `apt-config.private` (it is in `.gitignore`).

```bash
cp -r apt-config apt-config.private
nano apt-config.private/bhf.conf
```

Replace `<mybeckhoff-mail>` and `<mybeckhoff-password>` in both lines.

## 6. Build the image

From the repository root:

```bash
make build-image
```

If you do not need `make`, build the sample directly:

```bash
cd tc31-xar-base
docker build --secret id=apt,src=../apt-config.private/bhf.conf --build-context apt-config=../apt-config.private --network host -t tc31-xar-base .
```

Verify:

```bash
docker images
```

## 7. Transfer the image to the Beckhoff IPC

Either build and deploy on the IPC directly over SSH (`make build-image-remote` and `make deploy-containers`, see [`apt-config/README.md`](../apt-config/README.md); this needs `apt-config.private/target.conf` and makes the transfer unnecessary), push to a registry (`make push-image` with `REGISTRY` and `IMAGE_OWNER` set; see `mk/common.mk`), or copy the image over SSH:

```bash
docker save tc31-xar-base:latest | gzip | ssh <user>@<ipc-address> 'gunzip | sudo docker load'
```

Then continue with step 2 (firewall) and step 3 (start the containers) of the main [README](../README.md) on the IPC.

## Troubleshooting

- **`Cannot connect to the Docker daemon`:** make sure systemd is enabled (step 2), then run `sudo systemctl enable --now docker`. Check that your user is in the `docker` group (`id`).
- **`unknown flag: --build-context` or `--secret` needs BuildKit:** install `docker-buildx` (step 3).
- **`Missing .../apt-config.private/bhf.conf`:** complete step 5.
- **`/bin/sh^M: bad interpreter` or similar:** the files were checked out with CRLF line endings, usually from a clone under Windows. Re-clone inside WSL (step 4).
- **Authentication errors (401) from `deb.beckhoff.com`:** verify your myBeckhoff credentials in `apt-config.private/bhf.conf`.
- **Corporate proxy or VPN problems with DNS in WSL:** configure the proxy for the Docker daemon, or set `generateResolvConf = false` and your own `nameserver` in `/etc/wsl.conf` and `/etc/resolv.conf`.
