#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${ROOT_DIR}/compose.yml"
SERVICE_NAME="openclaw"
CONFIG_DIR="/home/claw/.openclaw"
HOST_CONFIG_DIR="${OPENCLAW_HOST_CONFIG_DIR:-${ROOT_DIR}/agent-data/.openclaw}"
INIT_MARKER="${CONFIG_DIR}/.initialized"
ENV_FILE="${ROOT_DIR}/.env"
MASK_TOKEN_OUTPUT="${OPENCLAW_MASK_TOKEN_OUTPUT:-0}"

# Preferred bootstrap command; script falls back for newer/older OpenClaw CLIs.
OPENCLAW_INIT_CMD="${OPENCLAW_INIT_CMD:-openclaw init}"
AUTO_START="${AUTO_START:-0}"
FORCE_INIT="${FORCE_INIT:-0}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

run_compose() {
  docker compose -f "${COMPOSE_FILE}" "$@"
}

is_truthy_value() {
  local raw="${1:-}"
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_host_config_dir() {
  mkdir -p "${HOST_CONFIG_DIR}"
  mkdir -p "${HOST_CONFIG_DIR}/identity"
  mkdir -p "${HOST_CONFIG_DIR}/agents/main/agent"
  mkdir -p "${HOST_CONFIG_DIR}/agents/main/sessions"
  if [[ ! -d "${HOST_CONFIG_DIR}" ]]; then
    echo "Error: host config dir is not a directory: ${HOST_CONFIG_DIR}" >&2
    exit 1
  fi
}

fix_container_config_permissions() {
  # Ensure mounted config tree is writable by the runtime user inside container.
  if ! run_compose run --rm --user root --entrypoint /bin/bash "${SERVICE_NAME}" -lc \
    "mkdir -p '${CONFIG_DIR}/identity' '${CONFIG_DIR}/agents/main/agent' '${CONFIG_DIR}/agents/main/sessions' && chown -R claw '${CONFIG_DIR}' && chmod -R u+rwX '${CONFIG_DIR}'"; then
    echo "Error: failed to fix permissions for ${CONFIG_DIR} inside container." >&2
    echo "Hint: check host ownership of ${HOST_CONFIG_DIR} and rerun setup." >&2
    exit 1
  fi

  if ! run_compose run --rm --entrypoint /bin/bash "${SERVICE_NAME}" -lc \
    "test -w '${CONFIG_DIR}' && mkdir -p '${CONFIG_DIR}/agents/main/agent' && touch '${CONFIG_DIR}/.write-test' && rm -f '${CONFIG_DIR}/.write-test'"; then
    echo "Error: ${CONFIG_DIR} is still not writable by user 'claw'." >&2
    echo "Hint: on Linux host, run: sudo chown -R \"$(id -u):$(id -g)\" '${HOST_CONFIG_DIR}'" >&2
    exit 1
  fi
}

upsert_env_key() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp

  tmp="$(mktemp)"
  if [[ -f "${file}" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "${line%%=*}" == "${key}" ]]; then
        printf '%s=%s\n' "${key}" "${value}" >>"${tmp}"
      else
        printf '%s\n' "$line" >>"${tmp}"
      fi
    done <"${file}"
  fi

  if ! grep -q "^${key}=" "${tmp}"; then
    printf '%s=%s\n' "${key}" "${value}" >>"${tmp}"
  fi
  mv "${tmp}" "${file}"
}

generate_gateway_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
    return 0
  fi
  return 1
}

display_gateway_token() {
  local token="$1"
  if ! is_truthy_value "${MASK_TOKEN_OUTPUT}"; then
    printf '%s' "${token}"
    return 0
  fi

  if [[ ${#token} -le 10 ]]; then
    printf '%s' "${token}"
    return 0
  fi
  printf '%s...%s' "${token:0:6}" "${token: -4}"
}

read_config_gateway_token() {
  run_compose run --rm --entrypoint /bin/bash "${SERVICE_NAME}" -lc "python3 - '${CONFIG_DIR}/openclaw.json' <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8') as f:
        cfg = json.load(f)
except Exception:
    raise SystemExit(0)

gateway = cfg.get('gateway')
if not isinstance(gateway, dict):
    raise SystemExit(0)
auth = gateway.get('auth')
if not isinstance(auth, dict):
    raise SystemExit(0)
token = auth.get('token')
if isinstance(token, str):
    token = token.strip()
    if token:
        print(token)
PY" 2>/dev/null || true
}

read_env_gateway_token() {
  local env_path="${ROOT_DIR}/.env"
  local line=""
  local token=""
  if [[ ! -f "${env_path}" ]]; then
    return 0
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" == OPENCLAW_GATEWAY_TOKEN=* ]]; then
      token="${line#OPENCLAW_GATEWAY_TOKEN=}"
    fi
  done <"${env_path}"

  if [[ -n "${token}" ]]; then
    printf '%s' "${token}"
  fi
}

run_openclaw_init() {
  local -a candidates=()
  local -a attempted=()
  local cmd=""

  # Keep user override highest priority, then try compatibility fallbacks.
  if [[ -n "${OPENCLAW_INIT_CMD}" ]]; then
    candidates+=("${OPENCLAW_INIT_CMD}")
  fi
  candidates+=(
    "openclaw onboard --mode local --no-install-daemon"
    "openclaw onboard"
  )

  for cmd in "${candidates[@]}"; do
    # Avoid retrying identical command strings.
    if [[ " ${attempted[*]} " == *" ${cmd} "* ]]; then
      continue
    fi
    attempted+=("${cmd}")

    if run_compose run --rm --entrypoint /bin/bash "${SERVICE_NAME}" -lc "${cmd}"; then
      INIT_CMD_USED="${cmd}"
      return 0
    fi
  done

  echo "Initialization command failed." >&2
  echo "Tried commands:" >&2
  for cmd in "${attempted[@]}"; do
    echo "  - ${cmd}" >&2
  done
  echo "Hint: set OPENCLAW_INIT_CMD to a working command for your OpenClaw version." >&2
  return 1
}

marker_exists() {
  run_compose run --rm --entrypoint /bin/bash "${SERVICE_NAME}" -lc "test -f '${INIT_MARKER}'" >/dev/null 2>&1
}

write_marker() {
  run_compose run --rm --entrypoint /bin/bash "${SERVICE_NAME}" -lc "mkdir -p '${CONFIG_DIR}' && touch '${INIT_MARKER}'"
}

require_cmd docker

if ! docker compose version >/dev/null 2>&1; then
  echo "Error: docker compose plugin is required." >&2
  exit 1
fi

# Automatically detect and export current user's UID/GID for container user matching
export HOST_UID="${HOST_UID:-$(id -u)}"
export HOST_GID="${HOST_GID:-$(id -g)}"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Error: compose file not found at ${COMPOSE_FILE}" >&2
  exit 1
fi

ensure_host_config_dir

echo "[1/3] Building image..."
run_compose build "${SERVICE_NAME}"

echo "[1.5/3] Fixing mounted config permissions..."
fix_container_config_permissions

echo "[2/3] Running OpenClaw initialization..."
if [[ "${FORCE_INIT}" == "1" ]] || ! marker_exists; then
  if ! run_openclaw_init; then
    exit 1
  fi
  write_marker
  echo "Initialization complete (command: ${INIT_CMD_USED:-unknown})."
else
  echo "Initialization already done (${INIT_MARKER} exists)."
fi

echo "[3/3] Setup finished."

GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"
TOKEN_SOURCE="env"
if [[ -z "${GATEWAY_TOKEN}" ]]; then
  GATEWAY_TOKEN="$(read_config_gateway_token)"
  TOKEN_SOURCE="config"
fi
if [[ -z "${GATEWAY_TOKEN}" ]]; then
  GATEWAY_TOKEN="$(read_env_gateway_token)"
  TOKEN_SOURCE="dotenv"
fi
if [[ -z "${GATEWAY_TOKEN}" ]]; then
  if ! GATEWAY_TOKEN="$(generate_gateway_token)"; then
    echo "Warning: unable to generate gateway token (missing openssl/python3 on host)." >&2
  else
    TOKEN_SOURCE="generated"
  fi
fi

if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" && -n "${GATEWAY_TOKEN}" ]]; then
  upsert_env_key "${ENV_FILE}" "OPENCLAW_GATEWAY_TOKEN" "${GATEWAY_TOKEN}"
  if [[ "${TOKEN_SOURCE}" == "generated" ]]; then
    echo "Generated gateway token and persisted it to ${ENV_FILE}."
  elif [[ "${TOKEN_SOURCE}" == "config" ]]; then
    echo "Reused gateway token from ${CONFIG_DIR}/openclaw.json and persisted it to ${ENV_FILE}."
  fi
fi

echo ""
echo "OpenClaw config"
echo "  container: ${CONFIG_DIR}"
echo "  host: ${HOST_CONFIG_DIR}"
echo "Workspace (host): ${ROOT_DIR}"
if [[ -n "${GATEWAY_TOKEN}" ]]; then
  echo "Gateway token (${TOKEN_SOURCE}): $(display_gateway_token "${GATEWAY_TOKEN}")"
else
  echo "Gateway token: not found yet (run init/login and rerun setup)."
fi

if [[ "${AUTO_START}" == "1" ]]; then
  echo "Starting service..."
  run_compose up "${SERVICE_NAME}"
else
  echo "Run 'docker compose -f ${COMPOSE_FILE} up ${SERVICE_NAME}' to start OpenClaw."
  if [[ -n "${GATEWAY_TOKEN}" ]]; then
    echo "Health check hint: docker compose -f ${COMPOSE_FILE} exec ${SERVICE_NAME} openclaw health --token \"${GATEWAY_TOKEN}\""
    if is_truthy_value "${MASK_TOKEN_OUTPUT}"; then
      echo "Set OPENCLAW_MASK_TOKEN_OUTPUT=0 to print full token in setup output."
    fi
  fi
fi

