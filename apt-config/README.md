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
