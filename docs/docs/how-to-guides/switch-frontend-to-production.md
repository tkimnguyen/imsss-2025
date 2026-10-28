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
new.imsss.net switched to a production build on October 28, 2026, following this guide.
Keep the guide for setting up another server, or for redoing the switch after a rollback.
For deploying changes now, see the deployment section of `devops/README.md`.
```

Before the switch, the frontend service ran `pnpm start`, the Volto development server.
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
  At the time of the switch, the server had 3.8 GB of RAM and only 512 MB of swap, and the development server used about 2 GB, so the frontend was stopped while building.
  A 2 GB swap file has been added since.
  On a server with less memory, use the build from CI instead of building on the server.
  The site is down for the few minutes the build takes.
  Adding swap makes the build more reliable; see the swap section of {doc}`../reference/server`.

## 1. Create the settings file

Volto reads some `RAZZLE_*` settings when it builds and others when it starts, so the build and the service must both use the same values.
Keep them in one file, `/etc/imsss-frontend.env`:

```ini
RAZZLE_PUBLIC_URL=https://new.imsss.net
RAZZLE_INTERNAL_API_PATH=http://localhost:8080/Plone
RAZZLE_BIND_ADDRESS=127.0.0.1
```

`RAZZLE_PUBLIC_URL`
:   The site's public address, used in links such as those in `robots.txt` and the sitemap.

`RAZZLE_INTERNAL_API_PATH`
:   Where the frontend fetches content while rendering pages on the server.
    Pointing it straight at the backend over plain HTTP avoids a round trip through `https://new.imsss.net`.
    That round trip is the likely source of the HTTPS errors that preceded the October 27, 2026, outage.

`RAZZLE_BIND_ADDRESS`
:   The network address the frontend listens on.
    Volto's production server listens on every interface by default, which exposes port 3000 to the internet when no firewall blocks it.
    `127.0.0.1` keeps it reachable only through nginx.

## 2. Build the frontend

In production, Volto looks up the site's add-ons from its own folder, `frontend/core/packages/volto`, when it starts.
`frontend/.npmrc` hoists the `@kitconcept/*` and `@eeacms/*` add-ons, which include the theme, into `frontend/node_modules` so that Volto can find them.
Without that, the production server fails at startup with `Cannot find module '@kitconcept/volto-light-theme'`.

The first `pnpm install` after the hoisting rules change rebuilds `node_modules` from scratch, which takes a few minutes.
The development server can't run while that happens, so stop the frontend first.
Then reinstall and build as `plone`, with the settings loaded.
`plone` can't use `sudo`, so run the `sudo` commands in a second SSH session as root, and the others as `plone`.

```shell
sudo systemctl stop imsss-frontend.service
cd ~/imsss.net-plone-6.1.3/imsss-2025/frontend
pnpm install --config.confirmModulesPurge=false
set -a; . /etc/imsss-frontend.env; set +a
pnpm build
```

`--config.confirmModulesPurge=false` lets pnpm rebuild `node_modules` without asking for confirmation.
Later installs don't need it.

The build writes its output to `frontend/core/packages/volto/build/`.
The development server also writes to that folder, so always rebuild before starting in production mode.
Otherwise the service runs the development server's output.

## 3. Change the service to run the build

Open an override file for the frontend unit:

```shell
sudo systemctl edit imsss-frontend.service
```

Add these lines, then save:

```ini
[Service]
EnvironmentFile=/etc/imsss-frontend.env
Environment="NODE_ENV=production"
ExecStart=
ExecStart=/home/plone/.nvm/versions/node/v22.21.1/bin/pnpm start:prod
ExecStartPost=/bin/sh -c 'until curl -fsS -o /dev/null http://127.0.0.1:3000/; do sleep 2; done'
TimeoutStartSec=120
```

`systemctl edit` saves the lines in `/etc/systemd/system/imsss-frontend.service.d/override.conf` and leaves the original unit file unchanged.

`EnvironmentFile`
:   Loads the same settings that the build used.

`ExecStart`
:   The empty `ExecStart=` line removes the development-server command before adding the new one.

`ExecStartPost`
:   Makes `systemctl start` and `systemctl restart` wait until the frontend serves a page.
    If it doesn't within `TimeoutStartSec`, the start fails and `systemctl status` shows an error.

## 4. Start the service and check the site

```shell
sudo systemctl daemon-reload
sudo systemctl start imsss-frontend.service
systemctl status imsss-frontend.service --no-pager
curl -s -o /dev/null -w '%{http_code}\n' https://new.imsss.net/
```

Then open the site in a browser **without** an SSH tunnel and check that it's styled, that you can log in, and that editing works.
Also check that port 3000 isn't reachable from outside, for example with `curl -m 8 http://new.imsss.net:3000/` from your own computer.

Browser tabs opened before the switch still run the development server's scripts.
Editing in such a tab fails with `Loading chunk Form failed`, naming a `localhost:3001` address.
Reloading the page fixes it.

## Deploy changes afterward

After the switch, deploy changes with `devops/scripts/deploy.sh`, which downloads a build made in CI instead of building on the server.
See the deployment section of `devops/README.md`.

## Roll back

To go back to the development server, remove the override and restart:

```shell
sudo systemctl revert imsss-frontend.service
sudo systemctl daemon-reload
sudo systemctl restart imsss-frontend.service
```
