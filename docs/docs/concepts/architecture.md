---
myst:
  html_meta:
    "description": "How new.imsss.net is put together: nginx, Volto, Plone, and the ZODB"
    "property=og:description": "How new.imsss.net is put together: nginx, Volto, Plone, and the ZODB"
    "property=og:title": "Architecture of new.imsss.net"
    "keywords": "Plone, IMSSS 2025, architecture, Volto, nginx, ZODB, REST API"
---

# Architecture of new.imsss.net

The site is a standard Plone 6 setup with two applications.

Plone (the backend)
:   Stores all content and serves it as JSON through the Plone REST API.
    It doesn't produce the pages visitors see.

Volto (the frontend)
:   A React application that fetches content from the backend and turns it into pages.
    It renders each page on the server for the first request, then runs in the visitor's browser and fetches further content directly from the REST API.

nginx sits in front of both, on the only ports open to the internet.

```{mermaid}
flowchart LR
    browser([Visitor's browser]) -- "HTTPS :443" --> nginx
    nginx -- "/++api++/…" --> plone["Plone backend<br/>127.0.0.1:8080"]
    nginx -- "every other path" --> volto["Volto frontend<br/>127.0.0.1:3000"]
    volto -- "content requests while rendering" --> plone
    plone --> zodb[("Data.fs + blobs")]
```

## How a page request flows

1.  A visitor requests `https://new.imsss.net/about-imsss/council-members`.
2.  nginx terminates TLS and forwards the request to Volto on port 3000.
3.  Volto asks Plone for the page's content, renders the HTML, and returns it with links to the site's JavaScript and CSS.
4.  The browser loads that JavaScript, and Volto takes over in the browser.
    When the visitor follows a link, Volto requests only the content, from `https://new.imsss.net/++api++/...`.
5.  nginx sends those `/++api++` requests straight to Plone.

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
See {doc}`../how-to-guides/back-up-and-restore`.

## Where the code and theme live

This repository holds both applications.

- `backend/` installs Plone 6.1 and the `imsss_2025` policy package.
- `frontend/packages/volto-imsss-2025/` is the site's Volto add-on.
  It depends on `@kitconcept/volto-light-theme`, which provides the site's look, and on `@eeacms/volto-hero-block`.
  The add-on's `src/theme/_main.scss` holds the site's own style changes.

The server runs a git checkout of this repository.
For the details of the server and its services, see {doc}`../reference/server`.

## The development server

The frontend on the server currently runs as Volto's development server.
That server is designed for a developer's own computer: it compiles code as files change, and it tells the browser to load JavaScript and CSS from `http://localhost:3001`.
On a public site, that address points at each visitor's own computer, so the page loads without scripts or styles unless the visitor has an SSH tunnel open to the server.
A production build serves those files from the site's own address.
See {doc}`../how-to-guides/switch-frontend-to-production`.
