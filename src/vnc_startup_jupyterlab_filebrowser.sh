#!/bin/bash
### every exit != 0 fails the script
set -e

# Setup logging
LOGS_DIR="/workspace/visomaster/Logs"
mkdir -p $LOGS_DIR
LOG_FILE="$LOGS_DIR/entrypoint_$(date +%Y%m%d_%H%M%S).log"

# Log function
log() {
  local level=$1
  local message=$2
  echo "$(date +"%Y-%m-%d %H:%M:%S") - $level - $message" | tee -a "$LOG_FILE"
}

# Error handling
error_handler() {
  local exit_code=$?
  local line_number=$1
  log "ERROR" "Error on line $line_number with exit code $exit_code"
  exit $exit_code
}
trap 'error_handler $LINENO' ERR

# Start logging
log "INFO" "=== VNC Startup Script Started ==="
log "INFO" "Log file: $LOG_FILE"

## print out help
help (){
echo "
USAGE:
docker run -it -p 6901:6901 -p 5901:5901 consol/<image>:<tag> <option>

IMAGES:
consol/debian-xfce-vnc
consol/rocky-xfce-vnc
consol/debian-icewm-vnc
consol/rocky-icewm-vnc

TAGS:
latest  stable version of branch 'master'
dev     current development version of branch 'dev'

OPTIONS:
-w, --wait      (default) keeps the UI and the vncserver up until SIGINT or SIGTERM will received
-s, --skip      skip the vnc startup and just execute the assigned command.
                example: docker run consol/rocky-xfce-vnc --skip bash
-d, --debug     enables more detailed startup output
                e.g. 'docker run consol/rocky-xfce-vnc --debug bash'
-h, --help      print out this help

Fore more information see: https://github.com/ConSol/docker-headless-vnc-container
"
}
if [[ $1 =~ -h|--help ]]; then
    help
    exit 0
fi

# should also source $STARTUPDIR/generate_container_user
log "INFO" "Sourcing .bashrc"
source $HOME/.bashrc

# add `--skip` to startup args, to skip the VNC startup procedure
if [[ $1 =~ -s|--skip ]]; then
    log "INFO" "Skipping VNC startup, executing command directly"
    echo -e "\n\n------------------ SKIP VNC STARTUP -----------------"
    echo -e "\n\n------------------ EXECUTE COMMAND ------------------"
    echo "Executing command: '${@:2}'"
    exec "${@:2}"
fi
if [[ $1 =~ -d|--debug ]]; then
    log "INFO" "Debug mode enabled"
    echo -e "\n\n------------------ DEBUG VNC STARTUP -----------------"
    export DEBUG=true
fi

## correct forwarding of shutdown signal
cleanup () {
    log "INFO" "Received shutdown signal, cleaning up"
    kill -s SIGTERM $!
    exit 0
}
trap cleanup SIGINT SIGTERM

## resolve_vnc_connection
VNC_IP=$(hostname -i)
log "INFO" "VNC IP address: $VNC_IP"

## change vnc password
log "INFO" "Setting up VNC password"
echo -e "\n------------------ change VNC password  ------------------"
# first entry is control, second is view (if only one is valid for both)
mkdir -p "$HOME/.vnc"
PASSWD_PATH="$HOME/.vnc/passwd"

if [[ -f $PASSWD_PATH ]]; then
    log "INFO" "Purging existing VNC password settings"
    echo -e "\n---------  purging existing VNC password settings  ---------"
    rm -f $PASSWD_PATH
fi

if [[ $VNC_VIEW_ONLY == "true" ]]; then
    log "INFO" "Starting VNC server in VIEW ONLY mode"
    echo "start VNC server in VIEW ONLY mode!"
    #create random pw to prevent access
    echo $(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20) | vncpasswd -f > $PASSWD_PATH
fi
echo "$VNC_PW" | vncpasswd -f >> $PASSWD_PATH
chmod 600 $PASSWD_PATH


## start vncserver and noVNC webclient
log "INFO" "Starting noVNC"
echo -e "\n------------------ start noVNC  ----------------------------"
if [[ $DEBUG == true ]]; then echo "$NO_VNC_HOME/utils/novnc_proxy --vnc localhost:$VNC_PORT --listen $NO_VNC_PORT"; fi
$NO_VNC_HOME/utils/novnc_proxy --vnc localhost:$VNC_PORT --listen $NO_VNC_PORT > $STARTUPDIR/no_vnc_startup.log 2>&1 &
PID_SUB=$!
log "INFO" "noVNC started with PID: $PID_SUB"

#echo -e "\n------------------ start VNC server ------------------------"
log "INFO" "Checking for and removing old VNC locks"
#echo "remove old vnc locks to be a reattachable container"
vncserver -kill $DISPLAY &> $STARTUPDIR/vnc_startup.log \
    || rm -rfv /tmp/.X*-lock /tmp/.X11-unix &> $STARTUPDIR/vnc_startup.log \
    || echo "no locks present"

log "INFO" "Starting VNC server with depth:$VNC_COL_DEPTH resolution:$VNC_RESOLUTION"
echo -e "start vncserver with param: VNC_COL_DEPTH=$VNC_COL_DEPTH, VNC_RESOLUTION=$VNC_RESOLUTION\n..."

vnc_cmd="vncserver $DISPLAY -depth $VNC_COL_DEPTH -geometry $VNC_RESOLUTION PasswordFile=$HOME/.vnc/passwd --I-KNOW-THIS-IS-INSECURE"
if [[ ${VNC_PASSWORDLESS:-} == "true" ]]; then
  log "INFO" "VNC server configured for passwordless access"
  vnc_cmd="${vnc_cmd} -SecurityTypes None"
fi

if [[ $DEBUG == true ]]; then echo "$vnc_cmd"; fi
$vnc_cmd > $STARTUPDIR/no_vnc_startup.log 2>&1
if [ $? -ne 0 ]; then
    log "ERROR" "Failed to start VNC server"
    cat $STARTUPDIR/no_vnc_startup.log
else
    log "INFO" "VNC server started successfully"
fi

log "INFO" "Starting window manager"
echo -e "start window manager\n..."
$HOME/wm_startup.sh &> $STARTUPDIR/wm_startup.log
if [ $? -ne 0 ]; then
    log "ERROR" "Failed to start window manager"
    cat $STARTUPDIR/wm_startup.log
else
    log "INFO" "Window manager started successfully"
fi

## log connect options
log "INFO" "VNC environment started successfully"
echo -e "\n\n------------------ VNC environment started ------------------"
echo -e "\nVNCSERVER started on DISPLAY= $DISPLAY \n\t=> connect via VNC viewer with $VNC_IP:$VNC_PORT"
echo -e "\nnoVNC HTML client started:\n\t=> connect via http://$VNC_IP:$NO_VNC_PORT/?password=...\n"

log "INFO" "Starting filebrowser on port 8585"
echo -e "Starting filebrowser at port 8585..."
nohup filebrowser -r /workspace -p 8585 -a 0.0.0.0 --noauth > "$LOGS_DIR/filebrowser.log" 2>&1 &
if [ $? -ne 0 ]; then
    log "ERROR" "Failed to start filebrowser"
else
    log "INFO" "Filebrowser started successfully"
fi

log "INFO" "Starting VisoMaster application"
echo -e "Starting visomaster..."
python /workspace/visomaster/main.py > "$LOGS_DIR/visomaster.log" 2>&1 &
VISOMASTER_PID=$!
log "INFO" "VisoMaster started with PID: $VISOMASTER_PID"

if [[ $DEBUG == true ]] || [[ $1 =~ -t|--tail-log ]]; then
    log "INFO" "Tailing log files"
    echo -e "\n------------------ $HOME/.vnc/*$DISPLAY.log ------------------"
    # if option `-t` or `--tail-log` block the execution and tail the VNC log
    tail -f $STARTUPDIR/*.log $HOME/.vnc/*$DISPLAY.log
fi

log "INFO" "Startup complete, proceeding to wait/execute command phase"
if [ -z "$1" ] || [[ $1 =~ -w|--wait ]]; then
    log "INFO" "Entering wait mode for PID: $PID_SUB"
    wait $PID_SUB
else
    # unknown option ==> call command
    log "INFO" "Executing command: $@"
    echo -e "\n\n------------------ EXECUTE COMMAND ------------------"
    echo "Executing command: '$@'"
    exec "$@"
fi
