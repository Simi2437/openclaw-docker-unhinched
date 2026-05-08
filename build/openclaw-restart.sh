#!/bin/sh
# ---------------------------------------------------------------------------
# openclaw-restart  –  startet den openclaw-Gateway innerhalb des Containers
#                      über supervisorctl neu.
#
# Kein systemd, kein launchd, kein Docker-Socket nötig.
# Aufruf:  openclaw-restart
#          (oder von OpenClaw-Agents via shell-tool)
# ---------------------------------------------------------------------------
exec supervisorctl -c /etc/supervisor/supervisord.conf restart openclaw-gateway

