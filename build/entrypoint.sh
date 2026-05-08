#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Auto-update openclaw on every container start.
# Controlled via environment variable:
#   OPENCLAW_AUTO_UPDATE=1  (default: 1)
#   OPENCLAW_AUTO_UPDATE=0  to skip updates (e.g. for offline/air-gapped use)
#
# npm global prefix: ~/.npm-global  (gemountet vom Host → Updates bleiben erhalten)
# ---------------------------------------------------------------------------

log() { echo "[entrypoint] $*"; }

OPENCLAW_AUTO_UPDATE="${OPENCLAW_AUTO_UPDATE:-1}"

if [ "${OPENCLAW_AUTO_UPDATE}" = "1" ]; then
  log "--- openclaw install/update check ---"

  INSTALLED="$(openclaw --version 2>/dev/null | awk '{print $2}' || echo 'unknown')"
  log "installed version : ${INSTALLED}"

  # Erster Start: openclaw noch nicht installiert (leeres ~/.npm-global)
  if [ "${INSTALLED}" = "unknown" ] || [ -z "${INSTALLED}" ]; then
    log "openclaw nicht gefunden – Erstinstallation..."
    log "▶ npm install -g openclaw@latest"
    npm install -g openclaw@latest 2>&1 || { log "FEHLER: Erstinstallation fehlgeschlagen."; exit 1; }
    log "openclaw installiert: $(openclaw --version 2>/dev/null || echo 'unknown')"
  else
    log "▶ npm view openclaw version  (fetching latest from registry...)"
    LATEST="$(npm view openclaw version 2>/dev/null || echo 'unknown')"
    log "latest on registry: ${LATEST}"

    if [ "${INSTALLED}" = "${LATEST}" ] || [ -z "${LATEST}" ] || [ "${LATEST}" = "unknown" ]; then
      log "already up-to-date (or registry unreachable), skipping install."
    else
      log "update available (${INSTALLED} → ${LATEST}), installing..."
      log "▶ npm install -g openclaw@latest"
      npm install -g openclaw@latest 2>&1 || log "WARNING: openclaw update failed, continuing with installed version."
      log "openclaw now at: $(openclaw --version 2>/dev/null || echo 'unknown')"
    fi
  fi

  log "--- openclaw plugin update ---"
  log "▶ openclaw plugins update --all"
  openclaw plugins update --all 2>&1 || log "WARNING: openclaw plugin update failed, continuing."
  log "--- update complete ---"
else
  log "OPENCLAW_AUTO_UPDATE=0 – skipping update."
fi

log "▶ exec supervisord"
# supervisord übernimmt als Prozess-Manager:
#   - startet "openclaw gateway --bind lan" (siehe /etc/supervisor/supervisord.conf)
#   - startet es automatisch neu falls es abstürzt (autorestart=true)
#   - "openclaw-restart" ruft "supervisorctl restart openclaw-gateway" auf
#     → Gateway-Neustart vollständig im Container, kein systemd/Docker-Socket nötig
exec supervisord -c /etc/supervisor/supervisord.conf
