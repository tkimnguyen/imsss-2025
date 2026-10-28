#!/bin/bash
# Deploy a commit of this repository to new.imsss.net.
#
# The server doesn't build the frontend: the "production-build" job in
# .github/workflows/frontend.yml builds it in CI, and this script downloads
# that build. Run it on the server as root:
#
#   sudo /home/plone/imsss.net-plone-6.1.3/imsss-2025/devops/scripts/deploy.sh [COMMIT]
#
# COMMIT defaults to origin/main. The script needs a GitHub token that can
# read the repository's Actions artifacts, in /etc/imsss-deploy.env:
#
#   GITHUB_TOKEN=github_pat_...
set -euo pipefail

# This file is in the checkout that the script updates, so run from a copy.
if [ -z "${IMSSS_DEPLOY_COPY:-}" ]; then
    copy=$(mktemp /tmp/imsss-deploy.XXXXXX)
    cp "$0" "$copy"
    IMSSS_DEPLOY_COPY=$copy exec bash "$copy" "$@"
fi
trap 'rm -f "$IMSSS_DEPLOY_COPY"' EXIT

REPO=tkimnguyen/imsss-2025
CHECKOUT=/home/plone/imsss.net-plone-6.1.3/imsss-2025
VOLTO=$CHECKOUT/frontend/core/packages/volto
NODE_BIN=/home/plone/.nvm/versions/node/v22.21.1/bin
TOKEN_FILE=/etc/imsss-deploy.env
FRONTEND_SERVICE=imsss-frontend.service
BACKEND_SERVICE=imsss-backend.service

log() { echo "==> $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }
as_plone() { runuser -u plone -- env PATH="$NODE_BIN:/usr/local/bin:/usr/bin:/bin" CI=1 "$@"; }
git_plone() { as_plone git -C "$CHECKOUT" "$@"; }
changed() { git_plone diff --quiet "$CURRENT" "$TARGET" -- "$@" && return 1 || return 0; }

[ "$(id -u)" = 0 ] || fail "run this script as root"
[ -r "$TOKEN_FILE" ] || fail "$TOKEN_FILE is missing"
# shellcheck disable=SC1090
. "$TOKEN_FILE"
[ -n "${GITHUB_TOKEN:-}" ] || fail "GITHUB_TOKEN isn't set in $TOKEN_FILE"

# 1. Work out what to deploy.
[ -z "$(git_plone status --porcelain)" ] || fail "the checkout has uncommitted changes; commit or discard them first"
git_plone fetch --quiet origin
CURRENT=$(git_plone rev-parse HEAD)
TARGET=$(git_plone rev-parse --verify "${1:-origin/main}^{commit}")
git_plone merge-base --is-ancestor "$CURRENT" "$TARGET" ||
    fail "$TARGET doesn't follow the deployed commit $CURRENT"

# The frontend workflow only runs when the frontend changes, so use the build
# from the most recent commit that changed it.
FRONTEND_COMMIT=$(git_plone log -1 --format=%H "$TARGET" -- frontend .github/workflows/frontend.yml)
DEPLOYED_BUILD=$(cat "$VOLTO/build/BUILD_COMMIT" 2>/dev/null || true)
log "deploying $(git_plone log -1 --format='%h %s' "$TARGET")"

# Regenerating the instance configuration rewrites zope.conf, so leave it to a person.
if changed backend/instance.yaml; then
    fail "backend/instance.yaml changed; update the instance configuration by hand first"
fi

# 2. Download and check the frontend build before changing anything.
STAGING=""
if [ "$FRONTEND_COMMIT" != "$DEPLOYED_BUILD" ]; then
    log "downloading the frontend build for ${FRONTEND_COMMIT:0:7}"
    api() { curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$@"; }
    ARTIFACT_URL=$(api "https://api.github.com/repos/$REPO/actions/artifacts?name=frontend-build-$FRONTEND_COMMIT" |
        jq -r '[.artifacts[] | select(.expired | not)][0].archive_download_url // empty')
    [ -n "$ARTIFACT_URL" ] ||
        fail "no build for ${FRONTEND_COMMIT:0:7}; check that its CI run passed, or wait for it to finish"

    WORK=$(mktemp -d /tmp/imsss-build.XXXXXX)
    trap 'rm -f "$IMSSS_DEPLOY_COPY"; rm -rf "$WORK"' EXIT
    api -o "$WORK/artifact.zip" "$ARTIFACT_URL"
    python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$WORK/artifact.zip" "$WORK"

    STAGING=$VOLTO/build.new
    rm -rf "$STAGING"
    as_plone mkdir "$STAGING"
    as_plone tar -xzf "$WORK/frontend-build.tar.gz" -C "$STAGING" --strip-components=1
    [ -f "$STAGING/server.js" ] || fail "the downloaded build has no server.js"
    [ "$(cat "$STAGING/BUILD_COMMIT")" = "$FRONTEND_COMMIT" ] || fail "the downloaded build is for a different commit"
else
    log "the frontend build for ${FRONTEND_COMMIT:0:7} is already deployed"
fi

# 3. Update the code.
FRONTEND_DEPS_CHANGED=no
changed frontend/package.json frontend/pnpm-lock.yaml frontend/.npmrc frontend/mrs.developer.json \
    frontend/packages/volto-imsss-2025/package.json && FRONTEND_DEPS_CHANGED=yes
BACKEND_CHANGED=no
changed backend && BACKEND_CHANGED=yes
BACKEND_DEPS_CHANGED=no
changed backend/pyproject.toml backend/mx.ini backend/version.txt && BACKEND_DEPS_CHANGED=yes

log "updating the checkout to ${TARGET:0:7}"
git_plone merge --ff-only --quiet "$TARGET"

# 4. Install frontend dependencies if they changed. The frontend can't run
#    while node_modules is replaced.
if [ "$FRONTEND_DEPS_CHANGED" = yes ]; then
    log "frontend dependencies changed: stopping the frontend and reinstalling"
    systemctl stop "$FRONTEND_SERVICE"
    (cd "$CHECKOUT/frontend" && as_plone make install)
fi

# 5. Switch to the new build, and go back to the previous one if it doesn't start.
if [ -n "$STAGING" ]; then
    log "switching to the new frontend build"
    rm -rf "$VOLTO/build.prev"
    [ -d "$VOLTO/build" ] && mv "$VOLTO/build" "$VOLTO/build.prev"
    mv "$STAGING" "$VOLTO/build"
fi
if [ -n "$STAGING" ] || [ "$FRONTEND_DEPS_CHANGED" = yes ]; then
    if ! systemctl restart "$FRONTEND_SERVICE"; then
        if [ -d "$VOLTO/build.prev" ] && [ -n "$STAGING" ]; then
            log "the new build didn't start: going back to the previous one"
            rm -rf "$VOLTO/build.failed"
            mv "$VOLTO/build" "$VOLTO/build.failed"
            mv "$VOLTO/build.prev" "$VOLTO/build"
            systemctl restart "$FRONTEND_SERVICE" || true
        fi
        fail "the frontend didn't start; see journalctl -u $FRONTEND_SERVICE"
    fi
    log "the frontend is serving pages"
fi

# 6. Update backend dependencies if they changed, and restart the backend if
#    its code changed.
if [ "$BACKEND_DEPS_CHANGED" = yes ]; then
    log "backend dependencies changed: installing them"
    (cd "$CHECKOUT/backend" && as_plone make sync)
fi
if [ "$BACKEND_CHANGED" = yes ]; then
    log "backend changed: restarting it"
    systemctl restart "$BACKEND_SERVICE"
    for _ in $(seq 1 60); do
        curl -fsS -o /dev/null http://127.0.0.1:8080/Plone/++api++ && break
        sleep 2
    done
    curl -fsS -o /dev/null http://127.0.0.1:8080/Plone/++api++ || fail "the backend isn't responding"
    log "the backend is responding"
fi

# 7. Check the site from outside the server.
status=$(curl -s -o /dev/null -w '%{http_code}' https://new.imsss.net/)
[ "$status" = 200 ] || fail "https://new.imsss.net/ returned $status"
log "deployed $(git_plone log -1 --format='%h %s')"
