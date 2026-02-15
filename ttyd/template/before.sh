#!/usr/bin/env bash

# Export the module function if it exists
[[ $(type -t module) == "function" ]] && export -f module

# Export compute node the script is running on (already defined earlier, so no need to define again)
HOST="$host"
export host HOST

# Find available port to run server on
port=$(find_port)
PORT="$port"
export port PORT

# Generate SHA1 encrypted password (requires OpenSSL installed)
password="$(create_passwd 16)"
PASSWORD="$password"
export password PASSWORD

# Setup TMP Dir
TMPDIR="$(mktemp -d -p "/tmp" -t "$USER-tmpdir-XXXXXX")"
TMP_DIR="$TMPDIR"
chmod 700 "$TMPDIR"
export TMPDIR TMP_DIR

# Setup XDG_RUNTIME_DIR
XDG_RUNTIME_DIR="$(mktemp -d -p "/tmp" -t "$USER-xdgrun-XXXXXX")"
chmod 700 "$XDG_RUNTIME_DIR"
export XDG_RUNTIME_DIR

# Load Form Information
OOD_SR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
if [ -f "${OOD_SR}/form.sh" ]; then
  # shellcheck disable=SC1090,SC1091
  source "${OOD_SR}/form.sh"
fi
unset OOD_SR
