#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Auto-update openclaw on every container start.
# Controlled via environment variable:
#   OPENCLAW_AUTO_UPDATE=1  (default: 1)
#   OPENCLAW_AUTO_UPDATE=0  to skip updates (e.g. for offline/air-gapped use)
# ---------------------------------------------------------------------------

log() { echo "[entrypoint] $*"; }
run() { log "▶ $*"; "$@"; }

OPENCLAW_AUTO_UPDATE="${OPENCLAW_AUTO_UPDATE:-1}"

if [ "${OPENCLAW_AUTO_UPDATE}" = "1" ]; then
  log "--- openclaw core update ---"
  if run sudo npm install -g openclaw; then
    log "openclaw up-to-date: $(openclaw --version 2>/dev/null || echo 'version unknown')"
  else
    log "WARNING: openclaw core update failed, continuing with installed version." >&2
  fi

  # Update separately installed plugins (npm-tracked only; bundled plugins update with openclaw core above).
  # --yes is a global flag and must come before the subcommand for non-interactive use.
  log "--- openclaw plugin update ---"
  if run openclaw --yes plugins update --all; then
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
