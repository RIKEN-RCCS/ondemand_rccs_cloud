#!/usr/bin/env bash

# set environment variables
TMUX_SOCKET="J${SLURM_JOB_ID}.sock"
TMUX_SESSION="J${SLURM_JOB_ID}"
export TMUX_SOCKET TMUX_SESSION

# setup config file
if [ -f "${HOME}/.config/tmux/tmux.conf" ]; then
  TMUX_CONFIG_PATH="${HOME}/.config/tmux/tmux.conf"
elif [ -f "${HOME}/.tmux.conf" ]; then
  TMUX_CONFIG_PATH="${HOME}/.tmux.conf"
else
  mkdir -p "${HOME}/.config/tmux"
  cp -f "$OOD_STAGED_ROOT/tmux.conf" "${HOME}/.config/tmux/tmux.conf"
  TMUX_CONFIG_PATH="${HOME}/.config/tmux/tmux.conf"
  ln -sf "${HOME}/.config/tmux/tmux.conf" "${HOME}/.tmux.conf"
fi
export TMUX_CONFIG_PATH

# run app
ARCH=`arch`
VERSION=`rpm -E %{rhel}`
TMUX_PATH="/cloud_opt/ondemand/tmux/${ARCH}/r${VERSION}/bin/tmux"
$TMUX_PATH -f "$TMUX_CONFIG_PATH" -L "$TMUX_SOCKET" new -A -s "$TMUX_SESSION"
