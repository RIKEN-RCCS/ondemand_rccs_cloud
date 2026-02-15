# Wait for the Jupyter Notebook server to start
echo "Waiting for Jupyter Notebook server to open port ${port}..."
if wait_until_port_used "${host}:${port}" 600; then
  echo "TIMING - Wait ended at: $(date)"
else
  echo "TIMING - Wait ended at: $(date)"
  pkill -P ${SCRIPT_PID}
  clean_up 1
fi
sleep 2
