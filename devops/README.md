# DevOps Operations for IMSSS 2025 🚀

## How new.imsss.net is deployed today

> The Docker Swarm deployment described later in this document comes from the project template and is **not** how new.imsss.net currently runs.
> The live site runs directly from a git checkout on the server, as two systemd services behind nginx.
> There is no Docker on the server.

| Component | How it runs |
| --- | --- |
| Server | `new.imsss.net`, Ubuntu 24.04 LTS, 2 vCPU, 3.8 GB RAM, 25 GB disk |
| Code | A git checkout of this repository at `/home/plone/imsss.net-plone-6.1.3/imsss-2025`, owned by the `plone` user, on `main` |
| Backend | `imsss-backend.service` runs Plone 6.1.3 (Python 3.12) with `backend/.venv/bin/runwsgi backend/instance/etc/zope.ini`, listening on `127.0.0.1:8080`. The Plone site ID is `Plone`. |
| Database | ZODB FileStorage at `backend/instance/var/filestorage/Data.fs`, with images and files in `backend/instance/var/blobs`. There is no PostgreSQL. |
| Frontend | `imsss-frontend.service` runs a **production build** of Volto 18.29.1 with `pnpm start:prod`, listening on `127.0.0.1:3000`. Its settings are in `/etc/imsss-frontend.env`. |
| Web server | nginx, configured in `/etc/nginx/sites-enabled/plone.conf`. It terminates TLS, sends `/++api++` and `/robots.txt` to the backend (rewritten through the Virtual Host Monster to `/Plone`), and sends everything else to the frontend. HTTP redirects to HTTPS. |
| TLS certificate | Let's Encrypt, managed by the certbot snap. `snap.certbot.renew.timer` renews it automatically. |
| Firewall | `ufw` allows only SSH (22) and HTTP/HTTPS (80, 443) from outside. SSH accepts key logins only, and fail2ban bans addresses that repeatedly fail SSH logins. |
| Backups | The Linode Backup Service backs up the whole server, keeping about two weeks of backups. `imsss-backup.timer` also backs up the database and blobs to `/home/plone/backups` daily at 21:30 UTC, keeping 30 days. See "Backups" in `docs/docs/reference/server.md`. |

The systemd unit files live in `/etc/systemd/system/` on the server and are not in this repository.
Both units run as `plone` and use `Restart=on-failure`.
The frontend's production settings are in a drop-in, `/etc/systemd/system/imsss-frontend.service.d/override.conf`.
The frontend switched from the Volto development server to a production build on October 28, 2026.

### Deploy a change

The frontend is built in CI, not on the server.
For every push to `main` that changes the frontend, the `production-build` job in `.github/workflows/frontend.yml` builds it and uploads the build as an artifact named `frontend-build-<commit>`, kept for 90 days.
`devops/scripts/deploy.sh` downloads that build and deploys it.

1.  Push your commits to `main` on GitHub and wait until CI passes.
2.  On the server, run the deploy script as root.
    It deploys `origin/main` unless you give it a commit.

    ```shell
    ssh root@new.imsss.net
    /home/plone/imsss.net-plone-6.1.3/imsss-2025/devops/scripts/deploy.sh
    ```

The script:

- stops without changing anything if the checkout has uncommitted changes, if the build for the commit isn't available yet, or if `backend/instance.yaml` changed
- downloads and checks the frontend build before updating the code
- updates the checkout with a fast-forward merge
- reinstalls frontend dependencies, with the frontend stopped, if they changed
- switches to the new build and restarts the frontend, going back to the previous build if the new one doesn't start
- installs backend dependencies if they changed, and restarts the backend if `backend/` changed
- checks that `https://new.imsss.net/` responds

Because nothing is built on the server, the server needs only enough memory to run the site, about 700–800 MB.
On a server with 1 GB of memory, add a swap file first, as described in the "Swap" section of `docs/docs/reference/server.md`.

A frontend deploy makes the site unavailable only for the few seconds of the restart.
Visitors with the site already open may need to reload the page to get the new version.

The script reads a GitHub token from `/etc/imsss-deploy.env`, as `GITHUB_TOKEN=...`.
Use a fine-grained personal access token for `tkimnguyen/imsss-2025` only, with read access to Actions.
Keep the file owned by root with mode 600, and renew the token before it expires.

#### Backend configuration changes

The script installs backend dependencies itself when `backend/pyproject.toml`, `backend/mx.ini`, or `backend/version.txt` change.
It stops if `backend/instance.yaml` changed, because regenerating the instance configuration rewrites `backend/instance/etc/zope.conf`, which may have been edited on the server.
Compare the change with the server's `zope.conf`, apply it by hand, commit any resulting change, and run the script again.

#### Build on the server instead

Building the frontend needs about 3 GB of memory.
On a server with enough memory, you can still build it there, with the frontend stopped for the few minutes the build takes:

```shell
sudo systemctl stop imsss-frontend.service
cd ~/imsss.net-plone-6.1.3/imsss-2025/frontend
set -a; . /etc/imsss-frontend.env; set +a
pnpm build
sudo systemctl start imsss-frontend.service
```

### Check status and logs

```shell
systemctl status imsss-frontend.service imsss-backend.service nginx
journalctl -u imsss-frontend.service -n 100 --no-pager    # frontend output and errors
journalctl -u imsss-backend.service -n 100 --no-pager     # backend output and errors
sudo tail -n 50 /var/log/nginx/new.imsss.net.error.log
ss -ltn | grep -E ':3000|:8080'                           # are both apps listening?
sudo ufw status                                           # firewall rules
```

If the frontend crashes, systemd restarts it after 5 seconds.
If the site keeps returning `502 Bad Gateway`, see the "Fix a 502 Bad Gateway error" guide in `docs/`.

### Reach the apps from your computer

Both apps listen only on the server's loopback interface.
To reach them from your computer, open a tunnel:

```shell
ssh plone@new.imsss.net -L8080:localhost:8080 -L3000:localhost:3000
```

While the tunnel is open, `localhost:3000` and `localhost:8080` on your computer point to the server, so don't run a local Volto or Plone at the same time.

## The template's Docker deployment (not in use)

Welcome to the DevOps documentation for IMSSS 2025! In this guide, we'll walk you through the setup and deployment process, ensuring a smooth and efficient development workflow. We leverage the power of [Ansible](https://www.ansible.com/), [Docker](https://www.docker.com/), and [Docker Swarm](https://docs.docker.com/engine/swarm/) to automate, containerize, and orchestrate application deployment. 🛠️🐳🌐

- **Ansible** empowers us to automate tasks like software provisioning, configuration management, and application deployment. It's like having a robot assistant that takes care of the repetitive tasks, freeing you to focus on more strategic activities! 🤖✨

- **Docker** encapsulates our application and its dependencies into a container to ensure consistency across multiple development, testing, and deployment environments. It's like packing your entire application, including the environment it runs in, into a portable box that you can run anywhere! 📦🚀

- **Docker Swarm** takes it a step further by turning a group of Docker engines into a single, virtual Docker engine. It allows us to deploy our containers across multiple machines, enhancing availability and scalability. It's like having a swarm of bees working harmoniously to build, run, and scale your application! 🐝🌟

### Our Docker Stack 📚

We deploy a robust website running [Plone](https://plone.org/) using a Docker stack that consists of:

- **Traefik:** Serves as the router and SSL termination, integrated with [Let's Encrypt](https://letsencrypt.org/) for free SSL certificates, ensuring that our website is secure and trusted. 🔒🌐

- **Plone Frontend using Volto:** A modern, fast, React-based frontend that delivers an exceptional user experience. It's like having a sleek, high-performance car to navigate the web! 🏎️💨

- **Plone Backend:** Responsible for the API, it's the engine under the hood, ensuring that data is processed, stored, and retrieved efficiently. 🏭🚀

- **Postgres 14 Database:** A reliable, robust database to store the site data, ensuring that our content is safe, secure, and quickly accessible. 🗃️⚡


Now, let’s dive into the setup! 🏊‍♂️💫
## Setup

Ensure you navigate to the `devops` folder before executing any commands listed in this document. From the root of your repository, execute:

```shell
cd devops
```

### Environment Configuration

Start by creating an `.env` file in the `devops` folder. You can copy the existing `.env_dist` file as a starting point:

```shell
cp .env_dist .env
```

Edit the `.env` file to suit your environment. For example:

```
ANSIBLE_REMOTE_PORT=22
DEPLOY_ENV=prod
DEPLOY_HOST=new.imsss.net
DEPLOY_PORT=22
DEPLOY_USER=plone
DOCKER_CONFIG=.docker
STACK_NAME=new-imsss-net
```

Note: The `.env` file is included in `.gitignore`, ensuring environment-specific configurations aren't pushed to the repository.


### Server installation

You need either a Ubuntu or Debian based system for new.imsss.net, enable SSH, and install a supported version of Python 3 on that system.


### Ansible Installation

Execute the following to create a Python 3 virtual environment and install Ansible along with its dependencies:

```shell
make setup
```

### Inventory Configuration

Modify `devops/inventory/hosts.yml` with the appropriate connection details:

```yaml
---
prod:
  hosts:
    new.imsss.net:
      ansible_user: root
      host: new
      hostname: new.imsss.net
```

## Server Setup

With the correct information in `devops/inventory/hosts.yml`, initiate the remote server setup:

```shell
make server-setup
```

This command executes the Ansible playbook `devops/playbooks/setup.yml` on the remote server, performing various setup tasks including user creation, SSH setup, Docker installation, and more.

## Project Deployment

### Docker Configuration

Ensure you're logged into your Docker account as the deployment uses public images. Then, create a new Docker context for the remote server:

```shell
make docker-setup
```

Verify the configuration with:

```shell
make docker-info
```

### Stack Deployment

Deploy the stack defined in `devops/stacks/new.imsss.net.yml` to the remote server with:

```shell
make stack-deploy
```

### Stack Status Verification

Check the status of all services in your stack:

```shell
make stack-status
```

### Plone Site Creation

If deploying for the first time, the frontend containers might not be `healthy` due to the absence of a configured Plone site on the backend. Create a new site with:

```shell
make stack-create-site
```

### Log Monitoring

Monitor logs for each service using the commands below:

- Traefik: ```make stack-logs-webserver```
- Frontend: ```make stack-logs-frontend```
- Backend: ```make stack-logs-backend```
