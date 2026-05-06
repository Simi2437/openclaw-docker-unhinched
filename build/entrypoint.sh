#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Auto-update openclaw on every container start.
# Controlled via environment variable:
#   OPENCLAW_AUTO_UPDATE=1  (default: 1)
#   OPENCLAW_AUTO_UPDATE=0  to skip updates (e.g. for offline/air-gapped use)
# ---------------------------------------------------------------------------

OPENCLAW_AUTO_UPDATE="${OPENCLAW_AUTO_UPDATE:-1}"

if [ "${OPENCLAW_AUTO_UPDATE}" = "1" ]; then
  echo "[entrypoint] Checking for openclaw core update..."
  if npm install -g openclaw 2>&1 | tail -n 3; then
    echo "[entrypoint] openclaw up-to-date: $(openclaw --version 2>/dev/null || echo 'version unknown')"
  else
    echo "[entrypoint] Warning: openclaw core update failed, continuing with installed version." >&2
  fi

  # Update separately installed plugins (npm-tracked only; bundled plugins update with openclaw core above).
  # --yes skips integrity-change prompts in non-interactive environments.
  echo "[entrypoint] Checking for openclaw plugin updates..."
  if openclaw plugins update --all --yes 2>&1 | tail -n 5; then
    echo "[entrypoint] openclaw plugins up-to-date."
  else
    echo "[entrypoint] Warning: openclaw plugin update failed, continuing." >&2
  fi
else
  echo "[entrypoint] OPENCLAW_AUTO_UPDATE=0 – skipping update."
fi

# Hand off to the actual command (e.g. "openclaw gateway")
exec "$@"



