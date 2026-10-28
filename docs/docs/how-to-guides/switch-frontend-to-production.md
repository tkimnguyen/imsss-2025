---
myst:
  html_meta:
    "description": "How to run the new.imsss.net frontend from a production build"
    "property=og:description": "How to run the new.imsss.net frontend from a production build"
    "property=og:title": "Switch the frontend to a production build"
    "keywords": "Plone, IMSSS 2025, Volto, production, build, systemd, deploy"
---

# Switch the frontend to a production build

```{note}
This guide describes a planned change.
As of October 2026, the frontend still runs as a development server.
Once you've made the switch, update {doc}`../reference/server` and the deployment section of `devops/README.md` to match.
```

The frontend service currently runs `pnpm start`, the Volto development server.
Running a production build instead:

- serves the site's JavaScript and CSS through nginx, so every visitor gets a styled site without an SSH tunnel
- lets systemd restart the frontend when it crashes, so a crash causes seconds of downtime instead of hours
- starts in seconds, because nothing is compiled at startup
- stops code changes from going live as soon as they're pulled, which also means every change needs a build

## Before you start

- Make sure the checkout on the server is clean and on the commit you want to deploy.

  ```shell
  cd ~/imsss.net-plone-6.1.3/imsss-2025
  git status
  git pull --ff-only
  ```

- The build can use about 3 GB of memory.
  The server has 3.8 GB of RAM and only 512 MB of swap, and the development server uses about 2 GB, so you'll stop the frontend while building.
  The site is down for the few minutes the build takes.
  Adding swap makes the build more reliable:

  ```shell
  sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
  sudo mkswap /swapfile && sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  ```

## 1. Build the frontend

```shell
cd ~/imsss.net-plone-6.1.3/imsss-2025/frontend
sudo systemctl stop imsss-frontend.service
pnpm build
```

The build writes its output to `frontend/core/packages/volto/build/`.

## 2. Change the service to run the build

Open an override file for the frontend unit:

```shell
sudo systemctl edit imsss-frontend.service
```

Add these lines, then save:

```ini
[Service]
Environment="NODE_ENV=production"
Environment="RAZZLE_PUBLIC_URL=https://new.imsss.net"
Environment="RAZZLE_INTERNAL_API_PATH=http://localhost:8080/Plone"
ExecStart=
ExecStart=/home/plone/.nvm/versions/node/v22.21.1/bin/pnpm start:prod
ExecStartPost=/bin/sh -c 'until curl -fsS -o /dev/null http://127.0.0.1:3000/; do sleep 2; done'
TimeoutStartSec=120
```

The empty `ExecStart=` line removes the development-server command before adding the new one.

`RAZZLE_PUBLIC_URL`
:   The site's public address, used in links such as those in `robots.txt` and the sitemap.

`RAZZLE_INTERNAL_API_PATH`
:   Where the frontend fetches content while rendering pages on the server.
    Pointing it straight at the backend over plain HTTP avoids a round trip through `https://new.imsss.net`.
    That round trip is the likely source of the HTTPS errors that preceded the October 27, 2026, outage.

`ExecStartPost`
:   Makes `systemctl start` and `systemctl restart` wait until the frontend serves a page.
    If it doesn't within `TimeoutStartSec`, the start fails and `systemctl status` shows an error.

## 3. Start the service and check the site

```shell
sudo systemctl daemon-reload
sudo systemctl start imsss-frontend.service
systemctl status imsss-frontend.service --no-pager
curl -s -o /dev/null -w '%{http_code}\n' https://new.imsss.net/
```

Then open the site in a browser **without** an SSH tunnel and check that it's styled, that you can log in, and that editing works.

## Deploy changes afterward

Every change now needs a pull, a build, and a restart.
You can save these steps as a script, for example `~/bin/imsss-deploy-frontend.sh`:

```shell
#!/bin/sh
set -eu
cd /home/plone/imsss.net-plone-6.1.3/imsss-2025
git pull --ff-only
cd frontend
sudo systemctl stop imsss-frontend.service
pnpm build
sudo systemctl start imsss-frontend.service   # waits until the site responds
echo "Deployed $(git log --oneline -1)"
```

If dependencies changed, run `make install` in `frontend/` before `pnpm build`.

## Roll back

To go back to the development server, remove the override and restart:

```shell
sudo systemctl revert imsss-frontend.service
sudo systemctl daemon-reload
sudo systemctl restart imsss-frontend.service
```
