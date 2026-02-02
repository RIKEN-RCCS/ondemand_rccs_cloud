#!/usr/bin/env bash

# benchmark info
echo "TIMING - Starting main script at: $(date)"

# reset module environment to default
#module -q reset

# set the TERM
export TERM="xterm-256color"

# Singularity setting
IMAGE="/cloud_opt/ondemand/rocky95_`arch`.sif"

export LANG=C
DIR=""
for d in /run /var/run/munge /var/spool/slurm /cloud_opt /lvs0 /hs /usr/lib/locale/locale-archive; do
  if [ -e $d ]; then
      DIR=$DIR,$d
  fi
done
export SINGULARITY_BINDPATH=${DIR#,}

OPTION=""
if [ -e /usr/local/cuda ]; then
  for d in `ls -d1 /usr/local/cuda*`; do
    export SINGULARITY_BINDPATH=$SINGULARITY_BINDPATH,$d
  done
  export SINGULARITY_BINDPATH=$SINGULARITY_BINDPATH,/opt/nvidia
  OPTION="--nv"
elif [ -e /opt/rocm ]; then
  for d in `ls -d1 /opt/rocm*`; do
      export SINGULARITY_BINDPATH=$SINGULARITY_BINDPATH,$d
  done
  for f in `ls -1 /usr/share/Modules/modulefiles/rocm`; do
      path=/usr/share/Modules/modulefiles/rocm/$f
      r=`realpath $path`
      SINGULARITY_BINDPATH=$SINGULARITY_BINDPATH,$r:$path
  done
  OPTION="--rocm"
fi

if [ -e /etc/openmpi-x86_64/openmpi-mca-params.conf ]; then
    export SINGULARITY_BINDPATH=$SINGULARITY_BINDPATH,/etc/openmpi-x86_64/openmpi-mca-params.conf
fi

# source ttyd function setup
#source "$OOD_STAGED_ROOT/ttyd.sh"

singularity exec ${OPTION} ${IMAGE} /usr/bin/bash -c "source $OOD_STAGED_ROOT/ttyd.sh"

# set working directory
cd "$HOME" || exit 7

# benchmark info
echo "TIMING - Starting ttyd at: $(date)"

# launch ttyd
#singularity exec --env PS1='\u@\h:\w\$ ' ${OPTION} ${IMAGE}
ttyd \
	-p "${PORT}" \
	-b "/node/${HOST}/${PORT}" \
	-t "fontSize=${OOD_FONT_SIZE}" \
	-t 'cursorStyle=bar' \
	-t 'cursorBlink=true' \
	-t 'theme={"background": "#282a36", "foreground": "#f8f8f2"}' \
	-c "ttyd:${PASSWORD}" \
	-W -m 1 \
	"$OOD_STAGED_ROOT/tmux.sh"

