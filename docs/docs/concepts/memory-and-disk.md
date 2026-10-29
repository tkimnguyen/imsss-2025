---
myst:
  html_meta:
    "description": "What was done on October 28 and 29, 2026, to reduce memory and disk use on the new.imsss.net server"
    "property=og:description": "What was done on October 28 and 29, 2026, to reduce memory and disk use on the new.imsss.net server"
    "property=og:title": "Memory and disk use on the server"
    "keywords": "Plone, IMSSS 2025, memory, disk space, swap, Linode, Volto, production build, journal, pnpm"
---

# Memory and disk use on the server

On October 28 and 29, 2026, the memory used by the frontend dropped from about 1.9 GB to about 200 MB, the whole server came to use about 650 MB, and its free disk space grew from 3.1 GB to 14 GB.
That made it possible to move from a 4 GB to a 1 GB Linode plan.
This page explains what was changed, and what keeps it that way.

| | Before, October 28 | After, October 29 |
| --- | --- | --- |
| Linode plan | 4 GB: 2 vCPU, 3.8 GB usable | 1 GB: 1 vCPU, 961 MB usable |
| Memory used by the whole server | not measured | about 650 MB, with no swap in use |
| Frontend | Volto development server, about 1.9 GB | Production build, about 200 MB |
| Swap | 512 MB | 2.5 GB |
| Disk | 87% full, 3.1 GB free | 41% full, 14 GB free |

For the server's current layout, see {doc}`../reference/server`.
For how small a server the site can run on, and the options that were considered, see {doc}`hosting-options`.

## Memory

### The production build, instead of the development server

Until October 28, 2026, the frontend ran Volto's development server, which compiles the code as it runs.
It used about 1.9 GB of memory on its own.
It also made pages load without styles for visitors; see {doc}`architecture`.

The frontend now runs a production build, compiled once ahead of time.
It uses about 200 MB, so the switch saved about 1.7 GB.
With it, the whole site, Plone, Volto, and nginx together, used about 520 MB.
See {doc}`../how-to-guides/switch-frontend-to-production`.

### Building in CI, instead of on the server

A production build needs about 2.5–3 GB of memory for the 3–4 minutes it runs.
During the builds on the server on October 28, 2026, the server got within about 390 MB of running out, even with 3.8 GB.

Since that day, the `production-build` job in GitHub Actions builds the frontend, and `devops/scripts/deploy.sh` downloads the build and swaps it in.
The server never builds, so its size only has to suit the running site.
See {doc}`../reference/ci`.

### Swap

The server had only a 512 MB swap partition.
A 2 GB swap file, `/swapfile`, was added on October 28, 2026, so that memory peaks, and reinstalling frontend dependencies during a deploy, can't run the server out of memory.
On the 1 GB plan it normally sits unused.
See "Swap" in {doc}`../reference/server`.

### Starting the frontend with `node`

The frontend service started the build through `pnpm start:prod`, which ran a second `pnpm`, which in turn ran `node build/server.js`.
The two `pnpm` processes did nothing but wait, using about 125 MB between them.
Since October 29, 2026, the service starts `node build/server.js` directly.
See "`imsss-frontend.service`" in {doc}`../reference/server`.

### The move to the 1 GB plan

With these changes, the server used about 650 MB in total, including Ubuntu itself, so it moved to Linode's 1 GB plan on October 29, 2026.
The resize kept the server's IP addresses and disks, and the site was down for a few minutes.

A smaller plan also shrinks limits that the kernel sets from the amount of memory.
The firewall's connection-tracking table dropped to 8,192 connections, and a bot filled it within seconds of booting, so the site stopped responding.
The table is now set to 65,536 connections, using about 20 MB of memory; see "Connection tracking" in {doc}`../reference/server`.

Since then, Cloudflare caches pages for visitors who aren't logged in, and blocks bots and scanners, so fewer requests reach Volto and Plone at all; see {doc}`../reference/cloudflare`.

### Not done: Docker

Moving to the Docker stack in `devops/` was considered and rejected.
Docker itself adds about 100–150 MB, and the stack adds a Varnish cache, cache purgers, and a second copy of the frontend, for an estimated total of about 1.0–1.1 GB, twice what the site uses now.

## Disk

On October 28, 2026, the 25 GB disk was 87% full, with 3.1 GB free.
Most of the space was taken by old projects, download caches, and logs that the live site doesn't use.
After the cleanup, it was 41% full, with 14 GB free, and it still was on October 29.

Before anything that might be the only copy of something was deleted, it was copied to the maintainer's Mac, in `~/imsss-server-archive-20261028`, about 2.8 GB.
The copied databases were checked against the server's copies first.

### Old projects and archives

| Removed | Size | What it was |
| --- | --- | --- |
| `~/imsss.net` | 3.0 GB | A checkout of the older `tkimnguyen/imsss.net` site, with its own database and some uncommitted files. Copied to the Mac first. |
| `~/clean-test-plone-6.1.3` | 1.6 GB | A test project made from the Plone project template |
| `/root/imsss.net migration 20251014` | 1.4 GB | The database and blobs from before the migration to this site. Copied to the Mac first. |
| `~/imsss.net-migration-20251014` | 364 MB | Migration archives |

### Caches

These are recreated when they're needed, for example when `deploy.sh` reinstalls dependencies.

| Removed | Size | What it was |
| --- | --- | --- |
| `~/.cache/Cypress` | 1.4 GB | The browser-testing tool, which never runs on the server |
| `~/.cache/uv` | 1.2 GB | Python package downloads |
| `~/.cache/pnpm` | 1.0 GB | The metadata cache of pnpm. This isn't the package store that the live site uses, which stays. |
| `~/.cache/node`, `pip`, `pipx`, and the apt cache | about 240 MB | Other download caches |
| Unused packages in the pnpm store, `~/.local/share/pnpm/store` | about 500 MB | `pnpm store prune` removed packages that the live site no longer uses, taking the store from 1.7 GB to 1.2 GB |
| Node.js 24 and `~/.nvm/.cache` | 261 MB | The site uses Node.js 22.21.1 |
| Old snap revisions of `certbot`, `core24`, and `snapd` | about 150–200 MB | Disabled revisions that snap keeps after updates |

### Logs

| Removed | Size | What it was |
| --- | --- | --- |
| The systemd journal, `/var/log/journal` | 2.4 GB, down to 167 MB | Logs back to July 2026, with no size limit set |
| `/var/log/btmp` and `btmp.1` | 243 MB | Records of 348,612 failed SSH logins |

The journal is now limited to 200 MB by `/etc/systemd/journald.conf.d/size.conf`, which sets `SystemMaxUse=200M`, so it can't grow back.

The failed logins were password-guessing attempts over SSH.
They led to turning off password logins over SSH and setting up fail2ban, the same day; see "Logging in to the server" and "fail2ban" in {doc}`../reference/server`.

## What uses the disk now

On October 29, 2026, 9.2 GB of the 25 GB was in use:

| What | Size |
| --- | --- |
| Ubuntu itself, under `/usr`, `/var/lib`, and `/boot` | about 4 GB |
| The swap file, `/swapfile` | 2 GB |
| The pnpm package store, `~/.local/share/pnpm/store`, which the frontend needs | 1.2 GB |
| The site's checkout, with its dependencies and the frontend build | about 750 MB |
| Logs, under `/var/log`, including the journal | about 270 MB |
| The daily backups, `~/backups` | about 50 MB, growing to a few hundred MB as they reach their 30 days |

## Keeping it this way

Most of this stays down by itself:

- The journal's limit keeps it at 200 MB.
- The daily backups delete their own files after 30 days, and the Linode backups are kept by Linode, outside the server; see {doc}`../how-to-guides/back-up-and-restore`.
- The server doesn't build the frontend, and `deploy.sh` keeps only one previous build, in `build.prev/`.

The download caches in `~/.cache` grow back a little each time dependencies are reinstalled.
To check memory and disk use, run these as root:

```shell
free -m                                    # memory and swap
df -h /                                    # disk
du -sh /home/plone/.cache /home/plone/.local/share/pnpm/store /var/log /home/plone/backups
journalctl --disk-usage
```

If `~/.cache` grows past a few hundred MB, it's safe to empty: `rm -rf /home/plone/.cache/*`.
To remove packages that the site no longer uses from the pnpm store, run this as root:

```shell
cd /home/plone/imsss.net-plone-6.1.3/imsss-2025/frontend
runuser -u plone -- env PATH=/home/plone/.nvm/versions/node/v22.21.1/bin:/usr/bin:/bin pnpm store prune
```
