---
myst:
  html_meta:
    "description": "How much memory new.imsss.net needs, and whether to put it behind Cloudflare"
    "property=og:description": "How much memory new.imsss.net needs, and whether to put it behind Cloudflare"
    "property=og:title": "Hosting options for new.imsss.net"
    "keywords": "Plone, IMSSS 2025, hosting, memory, Linode, Docker, Cloudflare, CDN"
---

# Hosting options for new.imsss.net

This page looks at two questions about how the site is hosted: how small a server it can run on, and whether it's worth putting it behind Cloudflare.
It reflects the site's setup as of October 29, 2026, when the server moved from a 4 GB to a 1 GB Linode plan.
For how the site is put together, see {doc}`architecture`.

## Server size

Until October 29, 2026, the server had 3.8 GB of memory, but the running site used only a fraction of that.
It now runs on Linode's 1 GB plan, with 1 vCPU, 961 MB of usable memory, and 2.5 GB of swap.

### Memory use

Measured on the 4 GB plan on October 28, 2026:

| Running all the time | Memory |
| --- | --- |
| Backend (Plone) | 263 MB |
| Frontend (production build) | 215 MB |
| nginx | 43 MB |
| Ubuntu itself, including systemd, the journal, and SSH | about 150–250 MB (estimate) |
| **Total** | **about 700–800 MB** |

Plone's cache and the frontend both use more memory as traffic grows.

On October 29, 2026, two changes reduced this for the 1 GB plan.
The frontend now starts with `node` directly instead of through `pnpm`, which saves about 125 MB.
And Ubuntu uses less of its memory as cache on a smaller server.
On the 1 GB plan, the server used about 650 MB in total, with the backend at about 260 MB and the frontend at about 220 MB, and no swap in use.

Building the frontend is what needs the memory.
`pnpm build` needs about 2.5–3 GB for the 3–4 minutes it runs.
During the builds on the server on October 28, 2026, the server had as little as about 390 MB free.

### Building in GitHub Actions

Since October 28, 2026, the server doesn't build the frontend.
The `production-build` job in GitHub Actions builds it, and `devops/scripts/deploy.sh` downloads that build, unpacks it, and restarts the frontend.
See {doc}`../reference/ci` for how the builds are made and named.

A deploy still runs `make install` for the frontend when its dependencies change, and `make sync` for the backend when its dependencies change.
Both need far less memory than a build.

So the server's size no longer has to allow for building.

### Other ways to deploy without building on the server

These were considered before choosing to build in CI.

Build on a maintainer's computer and copy it up
:   A maintainer runs `pnpm build` locally with the production settings, copies the `build/` folder to the server with `rsync`, and restarts the frontend.
    The build is plain JavaScript, so building on macOS and running on Linux works.
    But deploys then depend on one person's computer, and it's easy to deploy a build that doesn't match the code on the server.

Docker images
:   CI already builds Docker images of the frontend and backend, so the server would only need to download and run them.
    This doesn't save memory: Docker itself adds about 100–150 MB.
    It would also mean moving the database and uploaded files into Docker's storage, a larger migration than building in CI.
    The project template's full Docker setup also adds Traefik, Varnish, and cache purgers, and runs two copies of the frontend, which would double memory use to about 1.0–1.1 GB.

Keep building on the server, with a lot of swap
:   With 3–4 GB of swap, a build would probably finish, but it could take 15–30 minutes instead of 3–4.
    The site is unavailable while the frontend is stopped for the build.

### Choosing a server size

A 1 GB server works, with about 300 MB to spare and swap as a safety net.
A 2 GB server would leave room for Plone's cache and traffic peaks without relying on swap, and its second vCPU makes deploys faster.
Move up to it if the server starts relying on swap, or if pages become slow under load.

Resizing a Linode keeps its IP addresses, but restarts it, so the site is down for a few minutes.
After a move, update the resources listed in {doc}`../reference/server`.

A smaller plan also shrinks limits that the kernel sets from the amount of memory.
After the move to 1 GB, the firewall's connection-tracking table held only 8,192 connections.
Bots filled it within seconds of booting, and the site and SSH stopped responding, while the server itself looked healthy.
The table is now larger, and nginx closes unused connections sooner.
See "Connection tracking" and "nginx" in {doc}`../reference/server`.
After any resize, check the kernel log for `table full` messages:

```shell
journalctl -k -b | grep -c "table full"
```

## Cloudflare

Cloudflare's free plan would sit between visitors and the server.
Visitors would connect to Cloudflare, and Cloudflare would forward their requests to the server.

In short, Cloudflare would make the site faster for distant visitors and better protected against attacks and aggressive bots.
It wouldn't change how much memory the server needs, or how new code is deployed.
It's worth doing if bot traffic or attacks become a problem, provided the domain's DNS records are all copied across when it moves.

### What Cloudflare would add

Faster static files worldwide
:   The site's JavaScript, CSS, fonts, and images are sent with headers that let browsers cache them for a year.
    Cloudflare would keep copies of them in its data centers around the world.
    Visitors far from the server would load pages faster, and the server would send less data.

Protection from attacks and bots
:   Cloudflare absorbs floods of traffic and filters obvious bots before they reach the server.
    A small server running Plone and Volto can be overwhelmed by aggressive crawlers, so this is the most practical benefit.

The server's address is hidden
:   Visitors would only see Cloudflare's addresses.
    The firewall could then accept web traffic only from Cloudflare, so nothing could bypass it.

### What it wouldn't change

Pages would still be generated for each visit
:   By default, Cloudflare doesn't cache the pages themselves, so every page view would still go through Volto and Plone.
    A rule can tell Cloudflare to cache pages too, but it must never cache pages for logged-in editors, who are identified by an `auth_token` cookie.
    Check whether the free plan can make caching decisions based on a cookie before relying on such a rule.

Outages would still be visible
:   If the frontend stopped responding, visitors would see a Cloudflare error page instead of nginx's.
    Cloudflare's "Always Online" feature serves old snapshots of pages, but only in limited cases.

Memory and deployment
:   Plone and Volto would still run on the server, so it would need the same memory, and deploying would work the same way.

### What setting it up would involve

DNS
:   The whole `imsss.net` domain would move to Cloudflare's name servers.
    Every existing DNS record must be copied across exactly, **especially the email (MX) records**, and any records for other sites on the domain.
    A mistake here could stop email from arriving, so export the current records before the move and compare them afterward.

HTTPS
:   Cloudflare's "Full (strict)" SSL mode keeps the connection between Cloudflare and the server encrypted, using the server's existing Let's Encrypt certificate.
    Test certificate renewal again once the site is behind Cloudflare.

Visitor addresses
:   nginx and Plone would see Cloudflare's addresses instead of visitors' real ones.
    nginx's `real_ip` settings need to list Cloudflare's address ranges, so that logs and Plone's `X-Forwarded-For` header still show the real visitor.

Firewall (optional)
:   Ports 80 and 443 could be limited to Cloudflare's address ranges.
    Cloudflare changes those ranges from time to time, so the firewall rules would need occasional updates.

### Steps, if the site moves behind Cloudflare

1.  Export and keep a copy of all current DNS records.
2.  Move the DNS, and compare every record, especially email.
3.  Set the SSL mode to "Full (strict)" and configure nginx's `real_ip` settings.
4.  Test viewing the site, logging in, editing, and certificate renewal.
5.  Only then, if wanted, limit the firewall to Cloudflare's address ranges.

Cloudflare's free plan features change from time to time.
Check the current plan details, especially cookie-based caching rules, before deciding.
