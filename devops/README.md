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
| Frontend | `imsss-frontend.service` runs `pnpm --filter @plone/volto start`, which is the Volto 18.29.1 **development server**, listening on `127.0.0.1:3000` (plus a webpack dev server on `[::1]:3001`). |
| Web server | nginx, configured in `/etc/nginx/sites-enabled/plone.conf`. It terminates TLS, sends `/++api++` to the backend (rewritten through the Virtual Host Monster to `/Plone`), and sends everything else to the frontend. HTTP redirects to HTTPS. |
| TLS certificate | Let's Encrypt, managed by the certbot snap. `snap.certbot.renew.timer` renews it automatically. |
| Backups | **None are configured.** `Data.fs` and `blobs` exist only on the server's disk. |

The systemd unit files live in `/etc/systemd/system/` on the server and are not in this repository.
Both units run as `plone` and use `Restart=on-failure`.

### Known problems with the current setup

- **Visitors see an unstyled site.**
  The development server tells browsers to load the site's JavaScript and CSS from `http://localhost:3001`, which refers to each visitor's own computer.
  The site only looks right for someone forwarding those ports to the server through an SSH tunnel, as below.
  Running a production build of the frontend fixes this for everyone.

  ```shell
  ssh plone@new.imsss.net -L8080:localhost:8080 -L3000:localhost:3000 -L3001:localhost:3001
  ```

  While the tunnel is open, `localhost:3000`, `3001`, and `8080` on your computer point to the server, so don't run a local Volto or Plone at the same time.
  Without the tunnel, a local Volto development server on port 3001 will answer instead, and new.imsss.net will show your local build or its errors.
- **Frontend crashes can go unnoticed.**
  In development mode the Node.js process that serves pages can exit while the parent `pnpm` process keeps running.
  When that happens `systemctl status` still reports `active (running)`, systemd does not restart it, and nginx returns `502 Bad Gateway` until someone restarts the service.

### Deploy a change

1.  Push your commits to `main` on GitHub and check that CI passes.
2.  On the server, update the checkout.

    ```shell
    ssh plone@new.imsss.net
    cd ~/imsss.net-plone-6.1.3/imsss-2025
    git status          # should be clean; commit or discard any edits made on the server first
    git pull --ff-only
    ```

3.  The frontend development server picks up frontend changes on its own.
    For backend changes, or if the frontend is not responding, restart the service and wait until it serves pages again.

    ```shell
    sudo systemctl restart imsss-frontend.service && \
    until curl -fsS -o /dev/null http://127.0.0.1:3000/; do sleep 2; done && \
    echo "frontend is serving on :3000"
    ```

    The backend restarts the same way with `sudo systemctl restart imsss-backend.service`.

### Check status and logs

```shell
systemctl status imsss-frontend.service imsss-backend.service nginx
journalctl -u imsss-frontend.service -n 100 --no-pager    # frontend output and errors
journalctl -u imsss-backend.service -n 100 --no-pager     # backend output and errors
sudo tail -n 50 /var/log/nginx/new.imsss.net.error.log
ss -ltn | grep -E ':3000|:8080'                           # are both apps listening?
```

If the site returns `502 Bad Gateway`, look in the frontend journal for `sswp> !!! Script exited with code 1`.
That line means the frontend app server has stopped, and the service needs a restart.

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
