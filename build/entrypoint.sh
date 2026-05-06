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

  INSTALLED="$(openclaw --version 2>/dev/null || echo 'unknown')"
  log "installed version : ${INSTALLED}"

  log "▶ npm view openclaw version  (fetching latest from registry...)"
  LATEST="$(npm view openclaw version 2>/dev/null || echo 'unknown')"
  log "latest on registry: ${LATEST}"

  if [ "${INSTALLED}" = "${LATEST}" ]; then
    log "already up-to-date, skipping install."
  else
    log "update available (${INSTALLED} → ${LATEST}), installing..."
    log "▶ sudo npm install -g openclaw@latest"
    sudo npm install -g openclaw@latest --progress=true
    log "openclaw updated to: $(openclaw --version 2>/dev/null || echo 'unknown')"
  fi

  # Update separately installed plugins (npm-tracked only; bundled plugins update with openclaw core above).
  # --yes is a global flag and must come before the subcommand for non-interactive use.
  log "--- openclaw plugin update ---"
  log "▶ openclaw --yes plugins update --all"
  if openclaw --yes plugins update --all; then
    log "openclaw plugins up-to-date."
  else
    log "WARNING: openclaw plugin update failed, continuing." >&2
  fi

  log "--- update complete ---"
else
  log "OPENCLAW_AUTO_UPDATE=0 – skipping update."
fi

log "▶ exec $*"
# Hand off to the actual command (e.g. "openclaw gateway")
exec "$@"
