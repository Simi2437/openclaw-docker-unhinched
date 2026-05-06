#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Auto-update openclaw on every container start.
# Controlled via environment variable:
#   OPENCLAW_AUTO_UPDATE=1  (default: 1)
#   OPENCLAW_AUTO_UPDATE=0  to skip updates (e.g. for offline/air-gapped use)
# ---------------------------------------------------------------------------

log() { echo "[entrypoint] $*"; }

OPENCLAW_AUTO_UPDATE="${OPENCLAW_AUTO_UPDATE:-1}"

if [ "${OPENCLAW_AUTO_UPDATE}" = "1" ]; then
  log "--- openclaw core update check ---"

  INSTALLED="$(openclaw --version 2>/dev/null | awk '{print $2}' || echo 'unknown')"
  log "installed version : ${INSTALLED}"

  log "▶ npm view openclaw version  (fetching latest from registry...)"
  LATEST="$(npm view openclaw version 2>/dev/null || echo 'unknown')"
  log "latest on registry: ${LATEST}"

  if [ "${INSTALLED}" = "${LATEST}" ]; then
    log "already up-to-date, skipping install."
  else
    log "update available (${INSTALLED} → ${LATEST}), installing..."
    log "▶ npm install -g openclaw@latest"
    npm install -g openclaw@latest 2>&1 || log "WARNING: openclaw core update failed, continuing with installed version."
    log "openclaw now at: $(openclaw --version 2>/dev/null || echo 'unknown')"
  fi

  log "--- openclaw plugin update ---"
  log "▶ openclaw plugins update --all"
  openclaw plugins update --all 2>&1 || log "WARNING: openclaw plugin update failed, continuing."
  log "--- update complete ---"
else
  log "OPENCLAW_AUTO_UPDATE=0 – skipping update."
fi

log "▶ exec $*"
# Hand off to the actual command (e.g. "openclaw gateway")
exec "$@"
