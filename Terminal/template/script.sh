#!/usr/bin/env bash

# benchmark info
echo "TIMING - Starting main script at: $(date)"

# set the TERM
export TERM="xterm-256color"

# set working directory
cd "$HOME" || exit 7

# launch ttyd
TTYD_PATH="$(which --skip-alias --skip-functions ttyd)"
$TTYD_PATH \
  -p "${PORT}" \
  -b "/node/${HOST}/${PORT}" \
  -t "fontSize=${OOD_FONT_SIZE}" \
  -t 'cursorStyle=bar' \
  -t 'cursorBlink=true' \
  -t 'theme={"background": "#282a36", "foreground": "#f8f8f2"}' \
  -c "ttyd:${PASSWORD}" \
  -W -m 1 \
  "$OOD_STAGED_ROOT/tmux.sh"
