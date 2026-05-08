FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# Base tools + Node 24 + useful utilities OpenClaw may need
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    unzip \
    zip \
    jq \
    nano \
    vim \
    iputils-ping \
    net-tools \
    dnsutils \
    procps \
    sudo \
    openssh-client \
    ripgrep \
    fd-find \
    lsof \
    openssl \
 && rm -rf /var/lib/apt/lists/*

# NodeSource repo for Node 24
RUN mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list \
 && apt-get update \
 && apt-get install -y nodejs \
 && npm install -g npm@latest \
 && npm install -g pnpm \
 && rm -rf /var/lib/apt/lists/*

# Build args to match host user (prevents permission issues with mounted volumes)
# Must be declared BEFORE they are used in RUN/chown commands
ARG UID=1000
ARG GID=1000
ARG USER=claw

# OpenClaw global install (as root during build; runtime updates use sudo in entrypoint.sh)
RUN npm install -g openclaw


# Python packages (--break-system-packages required on Ubuntu 24.04 / PEP 668)
RUN pip install --break-system-packages requests


# Create group/user with explicit conflict handling so USER always resolves.
RUN set -eux; \
  if getent group "${GID}" >/dev/null 2>&1; then \
    existing_group="$(getent group "${GID}" | cut -d: -f1)"; \
    if [ "${existing_group}" != "${USER}" ]; then \
      groupmod -n "${USER}" "${existing_group}"; \
    fi; \
  else \
    groupadd -g "${GID}" "${USER}"; \
  fi; \
  if id -u "${USER}" >/dev/null 2>&1; then \
    current_uid="$(id -u "${USER}")"; \
    if [ "${current_uid}" != "${UID}" ]; then \
      if getent passwd "${UID}" >/dev/null 2>&1 && [ "$(getent passwd "${UID}" | cut -d: -f1)" != "${USER}" ]; then \
        echo "Requested UID ${UID} is already used by another account" >&2; \
        exit 1; \
      fi; \
      usermod -u "${UID}" "${USER}"; \
    fi; \
    usermod -g "${GID}" "${USER}"; \
  elif getent passwd "${UID}" >/dev/null 2>&1; then \
    existing_user="$(getent passwd "${UID}" | cut -d: -f1)"; \
    usermod -l "${USER}" -d "/home/${USER}" -m "${existing_user}"; \
    usermod -g "${GID}" "${USER}"; \
    usermod -s /bin/bash "${USER}"; \
  else \
    useradd -m -u "${UID}" -g "${GID}" -s /bin/bash "${USER}"; \
  fi; \
  mkdir -p "/home/${USER}/.openclaw"; \
  chown -R "${UID}:${GID}" "/home/${USER}"; \
  echo "${USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USER}"; \
  chmod 0440 "/etc/sudoers.d/${USER}"

USER ${USER}
WORKDIR /home/${USER}

# Entrypoint: auto-updates openclaw on every container start
COPY --chown=${USER}:${USER} build/entrypoint.sh /usr/local/bin/entrypoint.sh
# Switch to root briefly to chmod, then back to USER
USER root
RUN chmod +x /usr/local/bin/entrypoint.sh
USER ${USER}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
