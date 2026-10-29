---
myst:
  html_meta:
    "description": "Reference for the IMSSS 2025 GitHub Actions workflows"
    "property=og:description": "Reference for the IMSSS 2025 GitHub Actions workflows"
    "property=og:title": "GitHub Actions workflows"
    "keywords": "Plone, IMSSS 2025, GitHub Actions, CI, Docker, ghcr.io"
---

# GitHub Actions workflows

The workflows live in `.github/workflows/`.
None of them changes the live site.
The `production-build` job builds the frontend for it, and `devops/scripts/deploy.sh`, run on the server, deploys that build.
See the deployment section of `devops/README.md`.

## Main workflow (`main.yml`)

Runs on every push that changes `backend/`, `frontend/`, `docs/`, `devops/`, `.readthedocs.yaml`, or the workflow files themselves.
It can also be started by hand, from the {guilabel}`Actions` tab on GitHub or with `gh workflow run main.yml`.
A run started by hand runs every job, whatever changed.

A `config` job works out which parts of the repository changed and runs only the matching jobs:

| Job | Runs when this changes | What it does |
| --- | --- | --- |
| `backend` (`backend.yml`) | `backend/` | Checks formatting, lint, XML and ZCML, package metadata, and Python versions; runs the tests and coverage; builds `backend/Dockerfile` and pushes `ghcr.io/tkimnguyen/imsss-2025-backend`. |
| `frontend` (`frontend.yml`) | `frontend/` | Runs `make install`, `make lint`, `make ci-i18n`, and `make test`. If they pass, builds `frontend/Dockerfile`, which is a production Volto build, for `linux/amd64` and pushes `ghcr.io/tkimnguyen/imsss-2025-frontend`. On pushes to `main`, the `production-build` job also builds the frontend for new.imsss.net; see below. |
| `docs` (`docs.yml`) | `docs/` or `.readthedocs.yaml` | Checks links, builds the HTML documentation, and runs Vale style, grammar, and spelling checks. |
| `Final report` | always | Writes a table of the job results to the run summary. |

### Image tags

Each pushed image is tagged with:

- the branch name, for example `main`
- `sha-` followed by the short commit hash, for example `sha-94e6e74`
- `latest`, for pushes to the default branch

The live site doesn't use these images.

### Run the same checks locally

```shell
make lint          # from the repository root, or in backend/ or frontend/
make test
cd frontend && make ci-i18n
```

`make lint` in `frontend/` stops at the first failing tool, so a pass in ESLint can hide Prettier or Stylelint errors that follow.
Run `pnpm prettier` and `pnpm stylelint` in `frontend/` to see every problem at once.

### Frontend build for new.imsss.net

The `production-build` job in `frontend.yml` builds the frontend that new.imsss.net runs, so that the server never has to.
It runs for pushes to `main` that change the frontend, and for runs of the main workflow started by hand on `main`, after the code analysis passes.

- It copies the checkout to `/home/plone/imsss.net-plone-6.1.3/imsss-2025`, the same path as on the server, and builds there.
  The build embeds the absolute paths of the add-ons it was built with, so the paths must match.
- It builds with the same `RAZZLE_*` settings as `/etc/imsss-frontend.env` on the server.
  The values are set in the job's `env`, and must be kept in step with that file.
- It names the build after the most recent commit that changed `frontend/` or `frontend.yml`, which may be older than the commit being built.
  It writes that commit's hash to `build/BUILD_COMMIT`, and uploads `build/` as `frontend-build.tar.gz` in an artifact named `frontend-build-<commit>`, kept for 90 days.

`devops/scripts/deploy.sh` on the server downloads that artifact, looking it up by the same commit.
If the build has expired, start the main workflow by hand to make a new one.

## Cloudflare address ranges (`cloudflare-ranges.yml`)

Runs at 09:17 UTC on the first day of each month, and can be started by hand.
It compares `devops/cloudflare-ips.txt` with Cloudflare's published address ranges, and fails if they differ, listing the changes.
The server's firewall accepts web traffic only from the ranges in that file, so a failed run means the firewall needs updating; see "Cloudflare" in {doc}`server`.

GitHub emails a failed scheduled run to whoever last changed the workflow's schedule.
GitHub turns off scheduled workflows in a public repository after 60 days without commits, and emails a warning first.
If that happens, turn the workflow on again from the Actions tab.

## Varnish Image Creation (`varnish.yml`)

Builds and pushes a Varnish cache image from `devops/varnish/` when that folder changes.
The live site doesn't run Varnish.

## Manual Deployment of new.imsss.net (`manual_deploy.yml`)

Started by hand only.
It deploys the Docker stack in `devops/stacks/new.imsss.net.yml` with `kitconcept/docker-stack-deploy`.

```{warning}
Don't run this workflow against the current server.
The server doesn't run Docker, and the stack keeps its database in a new Docker volume (`vol-site-data`), so it would start without the site's existing `Data.fs` and blobs.
```

## Preview pull request on Read the Docs (`rtd-pr-preview.yml`)

Adds a link to the Read the Docs preview of the documentation to pull requests that change `docs/`.

## Check a run from the command line

With the GitHub CLI installed and logged in:

```shell
gh run list --limit 5
gh run view RUN_ID                       # jobs and their results
gh run view RUN_ID --log-failed          # logs of the failed steps
gh run watch RUN_ID --exit-status        # wait until a run finishes
```
