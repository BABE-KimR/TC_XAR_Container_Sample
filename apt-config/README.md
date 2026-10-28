# apt-config (template — do not edit)

This folder is the shared **template** for the apt configuration used by all samples in this repository. It must only ever contain the template data (placeholders such as `<mybeckhoff-mail>` and `<mybeckhoff-password>`). **Never put real credentials or other private data here.**

## Usage

1. Copy the template to a private folder at the repository root:

   ```bash
   cp -r apt-config apt-config.private
   ```

2. Edit `apt-config.private/bhf.conf` and replace `<mybeckhoff-mail>` and `<mybeckhoff-password>` with your myBeckhoff credentials.

`apt-config.private/` is listed in `.gitignore` and must stay untracked. All samples read their apt configuration (`bhf.conf`, `bhf.list`, `debian.sources.list`) from `apt-config.private` when building a container image.

Files:

- `bhf.conf` — apt/curl netrc credentials for `deb.beckhoff.com` and `deb-mirror.beckhoff.com`
- `bhf.list` — Beckhoff apt source
- `debian.sources.list` — Debian mirror sources served by Beckhoff
- `target.conf` — optional definition of a remote Beckhoff IPC (`TARGET_HOST`, `TARGET_USER`, `TARGET_PORT`, `TARGET_SSH_KEY`, `TARGET_DIR`) used by the remote build/deploy targets (`make build-image-remote`, `make deploy-containers`). Edit it in `apt-config.private` only.

## Remote build and deploy

With `apt-config.private/target.conf` filled in, the image can be built directly on the target, and the sample's compose files deployed to it:

```bash
make build-image-remote   # DOCKER_HOST=ssh://user@host; credentials are streamed as a build secret, never stored on the target
make deploy-containers    # copies the compose files to TARGET_DIR/<sample> and runs docker compose up -d
```

Requirements: SSH access with a key (set `TARGET_SSH_KEY`, or use ssh-agent / a `~/.ssh/config` alias as `TARGET_HOST`), and the target user must be in the `docker` group on the target. Password logins are intentionally not supported; use keys.
