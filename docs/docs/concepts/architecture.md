---
myst:
  html_meta:
    "description": "How new.imsss.net is put together: Cloudflare, nginx, Volto, Plone, and the ZODB"
    "property=og:description": "How new.imsss.net is put together: Cloudflare, nginx, Volto, Plone, and the ZODB"
    "property=og:title": "Architecture of new.imsss.net"
    "keywords": "Plone, IMSSS 2025, architecture, Cloudflare, Volto, nginx, ZODB, REST API"
---

# Architecture of new.imsss.net

The site is a standard Plone 6 setup with two applications.

Plone (the backend)
:   Stores all content and serves it as JSON through the Plone REST API.
    It doesn't produce the pages visitors see.

Volto (the frontend)
:   A React application that fetches content from the backend and turns it into pages.
    It renders each page on the server for the first request, then runs in the visitor's browser and fetches further content directly from the REST API.

nginx sits in front of both on the server.
Since October 29, 2026, Cloudflare sits in front of nginx: visitors connect to Cloudflare, and the server's firewall accepts web traffic only from Cloudflare.

```{mermaid}
flowchart LR
    browser([Visitor's browser]) -- "HTTPS" --> cf["Cloudflare<br/>security rules, page cache"]
    cf -- "HTTPS :443" --> nginx
    nginx -- "/++api++/…" --> plone["Plone backend<br/>127.0.0.1:8080"]
    nginx -- "every other path" --> volto["Volto frontend<br/>127.0.0.1:3000"]
    volto -- "content requests while rendering" --> plone
    plone --> zodb[("Data.fs + blobs")]
```

## How a page request flows

1.  A visitor requests `https://new.imsss.net/about-imsss/council-members`.
2.  Cloudflare receives the request, and blocks it if it looks like an attack or comes from a bot.
    If the visitor isn't logged in and Cloudflare has a copy of the page from the last 5 minutes, it returns that copy, and the server never sees the request.
3.  Otherwise, Cloudflare forwards the request to nginx on the server, which forwards it to Volto on port 3000.
4.  Volto asks Plone for the page's content, renders the HTML, and returns it with links to the site's JavaScript and CSS.
5.  The browser loads that JavaScript, and Volto takes over in the browser.
    When the visitor follows a link, Volto requests only the content, from `https://new.imsss.net/++api++/...`.
6.  Cloudflare passes those `/++api++` requests on without caching them, and nginx sends them straight to Plone.

Logged-in editors have an `auth_token` cookie, so Cloudflare never serves them a cached page.
See {doc}`../reference/cloudflare` for its settings, and {doc}`hosting-options` for why the site uses it.

## Why nginx rewrites `/++api++` paths

The Plone site lives at `/Plone` inside Zope, but visitors see it at the root of `https://new.imsss.net`.
nginx rewrites `/++api++/about-imsss` to `/VirtualHostBase/https/new.imsss.net/Plone/++api++/VirtualHostRoot/about-imsss` before passing it to Plone.

The rewrite uses Zope's Virtual Host Monster.
It tells Plone which site to serve and which public address to use, so the URLs in Plone's responses read `https://new.imsss.net/...` instead of `http://localhost:8080/Plone/...`.

## Where the content lives

All content is stored in the ZODB, an object database, in two parts:

- `Data.fs` holds the pages, folders, settings, users, and every earlier version of them.
  New data is always appended to the end of the file.
- The `blobs` folder holds the contents of uploaded images and files, one file per version.

There is no separate database server.
Backing up the site means backing up these two parts together.

## Where the backups are kept

The content is backed up in three places, each covering a different kind of loss.

```{mermaid}
flowchart LR
    live[("Data.fs + blobs")] -- "daily, 21:30 UTC" --> local["/home/plone/backups<br/>30 days"]
    local -- "whole disk, daily" --> linode["Linode Backup Service<br/>about 2 weeks"]
    local -- "rsync, daily" --> mac["Maintainer's Mac<br/>months to years, thinned"]
```

Backups on the server
:   `repozo` backups of the database and an archive of the blobs, made every day.
    They're the quickest to restore from, for a content mistake, but they're lost with the server.

Linode backups
:   Copies of the whole disk, kept by Linode outside the server.
    They bring back the whole server, including its configuration, but only from the last two weeks.

The Mac's copy
:   The server's backups, copied every day with a key that can only read them.
    It keeps a thinned history, and it's outside Linode, so it survives losing the Linode account too.

See {doc}`../how-to-guides/back-up-and-restore` and {doc}`../how-to-guides/recover-the-server`.

## Where the code and theme live

This repository holds both applications.

- `backend/` installs Plone 6.1 and the `imsss_2025` policy package.
- `frontend/packages/volto-imsss-2025/` is the site's Volto add-on.
  It depends on `@kitconcept/volto-light-theme`, which provides the site's look, and on `@eeacms/volto-hero-block`.
  The add-on's `src/theme/_main.scss` holds the site's own style changes.

The server runs a git checkout of this repository.
For the details of the server and its services, see {doc}`../reference/server`.

## How a change reaches the site

The server doesn't build the frontend, because a build needs about 3 GB of memory.
CI builds it instead, and a script on the server deploys that build.

```{mermaid}
flowchart LR
    push["Push to main"] --> ci["CI: lint and test,<br/>then production build"]
    ci -- "artifact frontend-build-&lt;commit&gt;" --> gh[(GitHub)]
    deploy["deploy.sh on the server"] -- "download" --> gh
    deploy --> checkout["Update the checkout,<br/>swap builds, restart"]
```

1.  A push to `main` runs the CI workflow.
    When the frontend changed and the checks pass, the `production-build` job builds the frontend at the same path as the server's checkout, and stores the build on GitHub for 90 days.
2.  On the server, someone runs `devops/scripts/deploy.sh` as root.
    It downloads the build for the newest commit that changed the frontend, updates the checkout, swaps in the new build, and restarts what changed.
    If the new frontend doesn't start, the script goes back to the previous build.

Backend changes need no build: `deploy.sh` installs any new Python dependencies and restarts the backend.
See the deployment section of `devops/README.md` and {doc}`../reference/ci`.

## Development server and production build

Volto runs in one of two modes.

The development server
:   Compiles the code as files change and tells the browser to load JavaScript and CSS from `http://localhost:3001`.
    It's meant for a developer's own computer, where that address points at the development server itself.
    On a public site, that address points at each visitor's own computer, so pages load without scripts or styles.

The production build
:   Compiles everything once, ahead of time, and serves the JavaScript and CSS from the site's own address under `/static/`.
    It starts in seconds, and when it crashes its process exits, so systemd restarts it.

new.imsss.net ran the development server until October 28, 2026, and now runs a production build.
On your own computer, `make frontend-start` still runs the development server.
See {doc}`../how-to-guides/switch-frontend-to-production`.
