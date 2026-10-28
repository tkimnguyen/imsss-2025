---
myst:
  html_meta:
    "description": "How to bring new.imsss.net back after losing or breaking its server"
    "property=og:description": "How to bring new.imsss.net back after losing or breaking its server"
    "property=og:title": "Recover from losing the server"
    "keywords": "Plone, IMSSS 2025, disaster recovery, restore, Linode, backup, rebuild"
---

# Recover from losing the server

This guide brings new.imsss.net back when its server is broken beyond a quick fix, or gone.
For a frontend that's down but fixable, see {doc}`fix-a-502` first.
For a content mistake, such as a deleted page, see {doc}`back-up-and-restore`.

## What you need

- A login to Linode's Cloud Manager for the account that owns the server
- Access to the DNS settings for `imsss.net`, if the server's IP address changes
- An SSH key that can log in to the server as `root`, on your computer
- The maintainer's Mac, which holds a copy of the backups in `~/imsss-backups`, if the Linode backups can't be used
- A GitHub account with admin access to `tkimnguyen/imsss-2025`, to create a deploy token

## Choose a way back

The server still runs, but a change broke it
:   Restore the newest Linode backup over it.
    See [Restore the server over itself](#restore-the-server-over-itself).

The server is gone or won't boot, and Linode still has its backups
:   Create a new Linode from the newest backup.
    See [Create a new server from a Linode backup](#new-server-from-backup).

Linode's backups are gone too, for example after losing the Linode account
:   Build a new server and restore the content from the Mac's copy.
    See [Build a new server from scratch](#build-a-new-server-from-scratch).

Linode backups bring back the whole server, including its configuration, keys, and certificate, so they're much quicker than building from scratch.
Either way, the content is as of the newest backup.
Anything edited since that backup is lost.

(restore-the-server-over-itself)=
## Restore the server over itself

1.  In Cloud Manager, open the Linode, select the {guilabel}`Backups` tab, and find the newest backup from before the problem.
2.  From its menu, choose {guilabel}`Restore to Existing Linode`, choose this Linode, and select {guilabel}`Overwrite Linode`.
    The restore replaces the whole disk.
3.  Boot the Linode when the restore finishes, then follow [Check the site](#check-the-site).

If you're not sure the backup is good, restore it to a new Linode first, as described in {doc}`back-up-and-restore`, and check it there.

(new-server-from-backup)=
## Create a new server from a Linode backup

1.  In Cloud Manager, open the old Linode, select the {guilabel}`Backups` tab, and choose the newest backup.
2.  From its menu, choose {guilabel}`Deploy New Linode`.
    Pick a plan with at least 1 GB of memory.
    Linode creates it in the same region as the backup.
3.  When the new Linode is running, turn on the Backup Service for it under {guilabel}`Backups`.
    Backups belong to a Linode, so the new one starts with none.
4.  Note the new Linode's IPv4 and IPv6 addresses, then change the `A` and `AAAA` records for `new.imsss.net` to them.
5.  Wait for the DNS change to reach you.

    ```shell
    dig +short new.imsss.net A
    ```

6.  Follow [Check the site](#check-the-site).
7.  Delete the old Linode once the new one works, to stop paying for it.
    Its backups are deleted with it.

The new Linode has the old server's SSH host keys, accounts, certificate, deploy token, and backups, so nothing else needs changing.

(build-a-new-server-from-scratch)=
## Build a new server from scratch

This rebuilds the server as described in {doc}`../reference/server`.
It takes an hour or two.
Run the commands as root unless a step says `plone`.

### 1. Create the Linode

1.  In Cloud Manager, create a Linode with Ubuntu 24.04 LTS, at least 1 GB of memory, and your SSH public key as a root key.
    Turn on the Backup Service.
2.  Change the `A` and `AAAA` records for `new.imsss.net` to the new Linode's addresses.
    The HTTPS certificate in step 7 needs them.
3.  Remove the old server's host key from your computer, and log in.

    ```shell
    ssh-keygen -R new.imsss.net
    ssh root@new.imsss.net
    ```

### 2. Install packages and secure the server

```shell
apt update && apt upgrade -y
apt install -y nginx git make build-essential python3-dev python3.12-venv curl jq rsync fail2ban
snap install --classic certbot
```

Then set up, as described in {doc}`../reference/server`:

- the SSH settings in `/etc/ssh/sshd_config.d/00-imsss.conf`, from "Logging in to the server"
- the swap file, from "Swap"
- the journal limit, `/etc/systemd/journald.conf.d/size.conf` with `SystemMaxUse=200M`, then `systemctl restart systemd-journald`

Turn on the firewall:

```shell
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw enable
```

Create `/etc/fail2ban/jail.d/imsss.local`, replacing `YOUR-ADDRESS` with your own IP address, then restart fail2ban with `systemctl restart fail2ban`:

```ini
# new.imsss.net: ban addresses that keep failing SSH logins.
[DEFAULT]
# Never ban the server itself, or the maintainer's address.
ignoreip = 127.0.0.1/8 ::1 YOUR-ADDRESS

[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
# Ban repeat offenders for longer each time, up to a week.
bantime.increment = true
bantime.maxtime = 1w
```

### 3. Create the `plone` user

```shell
adduser --disabled-password --gecos "" plone
install -d -m 700 -o plone -g plone /home/plone/.ssh
install -m 600 -o plone -g plone /root/.ssh/authorized_keys /home/plone/.ssh/authorized_keys
```

Then add the Mac's backup key to `/home/plone/.ssh/authorized_keys`, restricted as described in "Set up the copy on a Mac" in {doc}`back-up-and-restore`.
Check that you can log in as `plone` with your key from another terminal.

### 4. Install the tools and the code, as `plone`

Log in as `plone`, then install uv, and Node.js 22.21.1 with nvm and pnpm.

```shell
curl -LsSf https://astral.sh/uv/install.sh | sh
. ~/.local/bin/env
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
. ~/.nvm/nvm.sh
nvm install 22.21.1
corepack enable
```

The services use `/home/plone/.nvm/versions/node/v22.21.1/bin/pnpm`, which `corepack enable` creates.

Clone the repository to the same path as before.
The services use this path, and CI builds the frontend for it.

```shell
mkdir -p ~/imsss.net-plone-6.1.3
git clone https://github.com/tkimnguyen/imsss-2025.git ~/imsss.net-plone-6.1.3/imsss-2025
cd ~/imsss.net-plone-6.1.3/imsss-2025
(cd backend && make install)
(cd frontend && make install)
```

`make install` in `backend/` creates the virtual environment and generates `backend/instance/`.
The `admin` password in `backend/instance.yaml` is used only for a new, empty database.
The restored database in the next step brings back the real `admin` password and every other user.

### 5. Restore the content

From the Mac, copy the backups to the new server with your own key, not the read-only backup key:

```shell
rsync -a ~/imsss-backups/filestorage ~/imsss-backups/blobs plone@new.imsss.net:backups/
```

Then, on the server as `plone`, restore the newest database backup and blob archive:

```shell
cd ~/imsss.net-plone-6.1.3/imsss-2025/backend
mkdir -p instance/var/filestorage
.venv/bin/repozo -R -r ~/backups/filestorage -o instance/var/filestorage/Data.fs
ls ~/backups/blobs | tail -1                 # the newest blob archive
tar -xzf ~/backups/blobs/blobs-YYYYMMDD.tar.gz -C instance/var
```

Use the blob archive from the same day as the newest database backup.

### 6. Set up the services, as root

1.  Create `/etc/systemd/system/imsss-backend.service`, `/etc/systemd/system/imsss-frontend.service`, its drop-in `/etc/systemd/system/imsss-frontend.service.d/override.conf`, and `/etc/imsss-frontend.env`, with the contents shown in "Services" in {doc}`../reference/server`.
2.  Start the backend, and turn on the frontend without starting it yet, because it has no build.

    ```shell
    systemctl daemon-reload
    systemctl enable --now imsss-backend.service
    systemctl enable imsss-frontend.service
    curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/Plone/++api++
    ```

3.  Create a new deploy token, as described in the deployment section of `devops/README.md`, and save it in `/etc/imsss-deploy.env`, owned by root, with mode 600.
    The old token was only on the lost server, so revoke it on GitHub.
4.  Deploy the frontend, which downloads the build from CI and starts it.

    ```shell
    /home/plone/imsss.net-plone-6.1.3/imsss-2025/devops/scripts/deploy.sh
    ```

    The script fails at the end, because nginx isn't set up yet, but the frontend is running.
    Check it with `curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/`.

CI keeps each build for 90 days, and builds only when a push changes the frontend.
If the frontend hasn't changed for longer than that, there's no build to download.
Then either push a change to the frontend and wait for CI, or create the Linode with 4 GB of memory, build on the server as described in the deployment section of `devops/README.md`, and resize the Linode afterward.

### 7. Set up nginx and the certificate, as root

1.  Create `/etc/nginx/sites-enabled/plone.conf`, and remove nginx's default site.
    The old server kept the default site, which only shows "Welcome to nginx!" for other host names, so the site doesn't need it.

    ```nginx
    upstream backend {
      server 127.0.0.1:8080;
    }
    upstream frontend {
      server 127.0.0.1:3000;
    }

    server {
      listen 80;
      server_name  new.imsss.net;
      client_max_body_size 10M;
      access_log  /var/log/nginx/new.imsss.net.access.log;
      error_log  /var/log/nginx/new.imsss.net.error.log;

      location ~ /\+\+api\+\+($|/.*) {
          rewrite ^/\+\+api\+\+($|/.*) /VirtualHostBase/https/$server_name/Plone/++api++/VirtualHostRoot/$1 break;
          proxy_pass http://backend;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto https;
      }

      location = /robots.txt {
          rewrite ^ /VirtualHostBase/https/$server_name:443/Plone/VirtualHostRoot/robots.txt break;
          proxy_pass http://backend;
          proxy_set_header Host $host;
      }

      location ~ / {
          location ~* \.(js|jsx|css|less|swf|eot|ttf|otf|woff|woff2)$ {
              add_header Cache-Control "public";
              expires +1y;
              proxy_pass http://frontend;
          }
          location ~* static.*\.(ico|jpg|jpeg|png|gif|svg)$ {
              add_header Cache-Control "public";
              expires +1y;
              proxy_pass http://frontend;
          }

          proxy_set_header        Host $host;
          proxy_set_header        X-Real-IP $remote_addr;
          proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header        X-Forwarded-Proto https;
          proxy_set_header        X-Forwarded-Port 443;
          proxy_redirect off;
          proxy_pass http://frontend;
      }
    }
    ```

    ```shell
    rm /etc/nginx/sites-enabled/default
    nginx -t && systemctl reload nginx
    ```

2.  Get the certificate.
    certbot changes the server to listen on port 443, and adds a server on port 80 that redirects to HTTPS.

    ```shell
    certbot --nginx -d new.imsss.net
    ```

3.  If certbot wrote `listen 443 ssl;` in `plone.conf`, change it to `listen 443 ssl http2;`, as on the old server, then run `nginx -t && systemctl reload nginx`.

### 8. Set up the backups

1.  Set up the daily backup, as described in "Schedule a daily database backup" in {doc}`back-up-and-restore`.
2.  On the Mac, accept the new server's host key, so that the daily copy can connect:

    ```shell
    ssh-keygen -R new.imsss.net
    ssh -i ~/.ssh/imsss_backup_pull plone@new.imsss.net
    ```

    Answer `yes` to the host key prompt.
    The connection then closes with an `rrsync` error, which is expected.

### 9. Update the docs

The rebuilt server differs from the old one in its creation dates, its deploy token, and possibly its plan.
Update {doc}`../reference/server` and the deployment section of `devops/README.md` to match.

(check-the-site)=
## Check the site

Run these on the server as root:

```shell
systemctl status imsss-backend.service imsss-frontend.service nginx --no-pager | grep -E "●|Active"
ss -ltn | grep -E ':3000|:8080'           # both on 127.0.0.1 only
ufw status
fail2ban-client status sshd
systemctl list-timers imsss-backup.timer snap.certbot.renew.timer
certbot certificates | grep -E "Domains|Expiry"
```

Then, from your own computer:

```shell
curl -s -o /dev/null -w '%{http_code}\n' https://new.imsss.net/    # 200
curl -m 8 http://new.imsss.net:3000/                                # times out
```

Finally, open the site in a browser, check that pages and images load and look right, log in, and edit and save a page.
In Cloud Manager, check that the Backup Service is on for the server.
The next day, check `~/imsss-backups/pull.log` on the Mac for a successful copy.
