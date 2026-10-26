# Return the site-specific settings required by the application.
#
# Returns:
# - xdg_data_home   (Hash): Base directory for application data storage, keyed by architecture
# - container_image (Hash): Container image used for job execution, keyed by architecture
#
def site_paths
  xdg_data_home = {
    "x86_64"  => "#{ENV['HOME']}/ondemand/x86_64",
    "aarch64" => "#{ENV['HOME']}/ondemand/aarch64"
  }
  container_image = {
    "x86_64"  => "/cloud_opt/ondemand/ubuntu2404_x86_64.sif",
    "aarch64" => "/cloud_opt/ondemand/ubuntu2404_aarch64.sif"
  }

  [xdg_data_home, container_image]
end

# Generate the Xfce startup shell script used by Open OnDemand applications.
#
# This method returns a Bash script that initializes the Xfce desktop
# environment inside the interactive session. 
#
# When virtualgl is true, the script enables VirtualGL support for
# hardware-accelerated OpenGL rendering (e.g., for visualization workloads).
#
def xfce_startup_script(virtualgl = false)
  <<~BASH
  #!/usr/bin/env bash
  
  # Change working directory to user's home directory
  cd "${HOME}"
  
  # Reset module environment (may require login shell for some HPC clusters)
  #module purge && module restore
  
  # Ensure that the user's configured login shell is used
  export SHELL="$(getent passwd $USER | cut -d: -f7)"
  
  # use a safe PATH to boot the desktop because dbus-launch can be
  # in another location from a python/conda installation and that will
  # conflict and cause issues. See https://github.com/OSC/ondemand/issues/700 for more.
  #SAFE_PATH="/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/bin"
  
  # Start up desktop
  #PATH="$SAFE_PATH" source "<%= session.staged_root.join("xfce.sh") %>"

  # Remove any preconfigured monitors
  if [[ -f "${HOME}/.config/monitors.xml" ]]; then
    mv "${HOME}/.config/monitors.xml" "${HOME}/.config/monitors.xml.bak"
  fi
  
  # Copy over default panel if doesn't exist, otherwise it will prompt the user
  PANEL_CONFIG="${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
  if [[ ! -e "${PANEL_CONFIG}" ]]; then
    mkdir -p "$(dirname "${PANEL_CONFIG}")"
    cp "/etc/xdg/xfce4/panel/default.xml" "${PANEL_CONFIG}"
  fi
  
  # Disable startup services
  xfconf-query -c xfce4-session -p /startup/ssh-agent/enabled -n -t bool -s false
  xfconf-query -c xfce4-session -p /startup/gpg-agent/enabled -n -t bool -s false
  
  # Disable useless services on autostart
  AUTOSTART="${HOME}/.config/autostart"
  rm -fr "${AUTOSTART}"    # clean up previous autostarts
  mkdir -p "${AUTOSTART}"
  for service in "pulseaudio" "rhsm-icon" "spice-vdagent" "tracker-extract" "tracker-miner-apps" "tracker-miner-user-guides" "xfce4-power-manager" "xfce-polkit"; do
    echo -e "[Desktop Entry]\nHidden=true" > "${AUTOSTART}/${service}.desktop"
  done

  # Run Xfce4 Terminal as login shell (sets proper TERM)
  TERM_CONFIG="${HOME}/.config/xfce4/terminal/terminalrc"
  if [[ ! -e "${TERM_CONFIG}" ]]; then
    mkdir -p "$(dirname "${TERM_CONFIG}")"
    sed 's/^ \{4\}//' > "${TERM_CONFIG}" << EOL
      [Configuration]
      CommandLoginShell=TRUE
  EOL
  else
    sed -i \
      '/^CommandLoginShell=/{h;s/=.*/=TRUE/};${x;/^$/{s//CommandLoginShell=TRUE/;H};x}' \
      "${TERM_CONFIG}"
  fi
  
  # launch dbus first through eval becuase it can conflict with a conda environment
  # see https://github.com/OSC/ondemand/issues/700
  eval $(dbus-launch --sh-syntax)

  # Enable VirtualGL
  _VIRTUALGL=""
  [ "#{virtualgl}" = "true" ] && _VIRTUALGL="vglrun -d egl"

  BASH
end

# Generates a Bash script snippet that configures GPU-related bind paths
# for Singularity containers.
#
# The script also sets the _OPTION variable (--nv or --rocm).
#
def gpu_bind_script
  <<~BASH
_OPTION=""
    append_bindpath() {
      local _path="$1"
      [ -z "${_path}" ] && return
      if [ -z "${SINGULARITY_BINDPATH:-}" ]; then
        export SINGULARITY_BINDPATH="${_path}"
      else
        export SINGULARITY_BINDPATH="${SINGULARITY_BINDPATH},${_path}"
      fi
    }

    if [ -e /usr/local/cuda ] || [ -e /opt/nvidia ]; then
      _OPTION="--nv"
      for dir in $(ls -d1 /usr/local/cuda* 2>/dev/null); do
        append_bindpath "${dir}"
      done
      [ -e /opt/nvidia ] && append_bindpath "/opt/nvidia"
      # --nv binds the NVIDIA libraries but not the GLVND vendor file, so libEGL
      # in the container only sees Mesa and VirtualGL silently falls back to llvmpipe
      if [ -e /usr/share/glvnd/egl_vendor.d/10_nvidia.json ]; then
        append_bindpath "/usr/share/glvnd/egl_vendor.d/10_nvidia.json"
        # Let a plain "vglrun" use the GPU via EGL; keep any value the user set
        export SINGULARITYENV_VGL_DISPLAY="${VGL_DISPLAY:-egl}"
      fi
    elif [ -e /opt/rocm ]; then
      _OPTION="--rocm"
      for dir in $(ls -d1 /opt/rocm* 2>/dev/null); do
        append_bindpath "${dir}"
      done
    fi
  BASH
end

# Generate the YAML for the script: section of submit.yml.erb
def job_script_yaml(name, queue, hours, gpus = "", email = "")
  yaml =  "  job_name: #{name}\n"
  yaml << "    queue_name: #{queue}\n"
  yaml << "    native:\n"

  gpus_option = gpus.to_s.strip.empty? ? "--gpus=1" : "--gpus=#{gpus}"

  case queue
  when "b300", "qc-a100", "ai-l40s", "ai-h200-brc" "ai-pro6000"
    yaml << "      - \"#{gpus_option} -t #{hours}:00:00\"\n"
  when "ai-h200-brc-pu"
    yaml << "      - \"#{gpus_option} -t 1:00:00\"\n"
  when "ai-h100l-pu"
    yaml << "      - \"-t 0:30:00\"\n"
  else
    yaml << "      - \"-t #{hours}:00:00\"\n"
  end

  unless email.blank?
    yaml << "    email: #{email}\n"
    yaml << "    email_on_started: true\n"
  end

  yaml
end

# Determine whether VGL is available for a given queue and GPU count.
def vgl_available?(queue, gpus)
  always_true = %w[
    a100
    ai-h100l
    ai-h100l-pu
    qc-h100
    qc-gh200
    ng-dgx-s
    ng-dgx-m0
    ng-dgx-m1
    ng-dgx-m2
    ng-dgx-m3
  ]

  gpu_dependent = %w[
    b300
    qc-a100
    ai-l40s
    ai-h200-brc
    ai-h200-brc-pu
    ai-pro6000
  ]

  always_false = %w[
    fx700
    mi100
    r340
    genoa
    genoa-m
    qc-mi210
    qc-mi250
    qc-pvc
    fs-mi300a
    fs-mi300x
    next-pvc
  ]

  return true  if always_true.include?(queue)
  # Form values arrive as strings, so convert before comparing
  return gpus.to_i > 0 if gpu_dependent.include?(queue)
  return false if always_false.include?(queue)

  false
end
