#!/usr/bin/env bash

set -e

# Define paths for your DanyBot API application
DANYBOT_API_DIR="${HOME}/danybot-api-v2"
DANYBOT_API_ENV="${DANYBOT_API_DIR}/env"
# DANYBOT_API_REPO="https://github.com/bdouglas89/vial_lab_pick_and_place.git"
DANYBOT_API_REPO="https://github.com/NotFabianML/danybot-api-v2.git"


# Function to install DanyBot API dependencies
function install_danybot_api_dependencies() {
  status_msg "Installing dependencies for DanyBot API..."
  
  # Install required system packages
  local dep=(git virtualenv)
  dependency_check "${dep[@]}"
  
  # Update system package lists if stale
  update_system_package_lists
  
  # Install required Python packages
  "${DANYBOT_API_ENV}/bin/pip" install -U pip
  "${DANYBOT_API_ENV}/bin/pip" install -r "${DANYBOT_API_DIR}/requirements.txt"
}

# Function to create Python virtual environment
function create_danybot_api_virtualenv() {
  status_msg "Creating Python virtual environment for DanyBot API..."

  [[ -d ${DANYBOT_API_ENV} ]] && rm -rf "${DANYBOT_API_ENV}"

  if virtualenv -p /usr/bin/python3 "${DANYBOT_API_ENV}"; then
    "${DANYBOT_API_ENV}/bin/pip" install -U pip
  else
    log_error "Failed to create Python virtual environment for DanyBot API"
    error_msg "Creation of DanyBot API virtual environment failed!"
    exit 1
  fi
}

# Function to setup DanyBot API
function danybot_api_setup() {
  status_msg "Cloning DanyBot API repository from ${DANYBOT_API_REPO}..."
  
  [[ -d ${DANYBOT_API_DIR} ]] && rm -rf "${DANYBOT_API_DIR}"
  git clone "${DANYBOT_API_REPO}" "${DANYBOT_API_DIR}"

  create_danybot_api_virtualenv
  install_danybot_api_dependencies

  create_danybot_api_service
}

# Function to create systemd service for DanyBot API
function create_danybot_api_service() {
  local service_file="/etc/systemd/system/danybot_api.service"

  status_msg "Creating systemd service for DanyBot API..."

  sudo bash -c "cat > ${service_file}" <<EOL
[Unit]
Description=DanyBot API
After=network.target

[Service]
User=${USER}
WorkingDirectory=${DANYBOT_API_DIR}
Environment="PATH=${DANYBOT_API_ENV}/bin"
ExecStart=${DANYBOT_API_ENV}/bin/python ${DANYBOT_API_DIR}/app.py --host="0.0.0.0"

[Install]
WantedBy=multi-user.target
EOL

  sudo systemctl daemon-reload
  sudo systemctl enable danybot_api.service
  sudo systemctl start danybot_api.service

  ok_msg "DanyBot API service created and started!"
}

function danybot_api_systemd() {
  local services
  local blacklist
  local ignore
  local match
# esto va en la linea 71
# ExecStart=${DANYBOT_API_ENV}/bin/python -m flask run
  ###
  # any moonraker client that uses "moonraker" in its own name must be blacklisted using
  # this variable, otherwise they will be falsely recognized as moonraker instances
  blacklist="obico"

  ignore="${SYSTEMD}/danybot_api-(${blacklist}).service"
  match="${SYSTEMD}/danybot_api(-[0-9a-zA-Z]+)?.service"

  services=$(find "${SYSTEMD}" -maxdepth 1 -regextype awk ! -regex "${ignore}" -regex "${match}" | sort)
  echo "${services}"
}

function get_danybot_api_status() {
  local sf_count status
  sf_count="$(danybot_api_systemd | wc -w)"

  ### remove the "SERVICE" entry from the data array if a danybot_api service is installed
  local data_arr=(SERVICE "${DANYBOT_API_DIR}" "${DANYBOT_API_ENV}")
  (( sf_count > 0 )) && unset "data_arr[0]"

  ### count+1 for each found data-item from array
  local filecount=0
  for data in "${data_arr[@]}"; do
    [[ -e ${data} ]] && filecount=$(( filecount + 1 ))
  done

  if (( filecount == ${#data_arr[*]} )); then
    status="Installed: ${sf_count}"
  elif (( filecount == 0 )); then
    status="Not installed!"
  else
    status="Incomplete!"
  fi

  echo "${status}"
}

# Function to display status messages
function status_msg() {
  echo -e "\033[1;34m$1\033[0m"
}

# Function to display error messages
function error_msg() {
  echo -e "\033[1;31m$1\033[0m"
}

# Function to display success messages
function ok_msg() {
  echo -e "\033[1;32m$1\033[0m"
}

# Function to check and install required dependencies
function dependency_check() {
  for dep in "$@"; do
    if ! dpkg -l | grep -qw $dep; then
      sudo apt-get install -y $dep
    fi
  done
}

# Function to update system package lists
function update_system_package_lists() {
  sudo apt-get update
}

# Main installation function
function install_danybot_api() {
  status_msg "Starting DanyBot API setup..."
  danybot_api_setup
  ok_msg "DanyBot API setup complete!"
}


function clone_danybot_api() {
  local repo=${1}

  status_msg "Cloning Moonraker from ${repo} ..."

  ### force remove existing danybot_api dir and clone into fresh danybot_api dir
  [[ -d ${DANYBOT_API_DIR} ]] && rm -rf "${DANYBOT_API_DIR}"

  cd "${HOME}" || exit 1
  if ! git clone "${DANYBOT_API_REPO}" "${DANYBOT_API_DIR}"; then
    print_error "Cloning Danybot Api from\n ${repo}\n failed!"
    exit 1
  fi
}

#==================================================#
#================ UPDATE MOONRAKER ================#
#==================================================#

function update_danybot_api() {
  do_action_service "stop" "danybot_api"

  if [[ ! -d ${DANYBOT_API_DIR} ]]; then
    clone_danybot_api "${DANYBOT_API_REPO}"
  else
    backup_before_update "danybot_api"
    status_msg "Updating Danybot Api ..."
    cd "${DANYBOT_API_DIR}" && git pull
    ### read PKGLIST and install possible new dependencies
    install_danybot_api_dependencies
    ### install possible new python dependencies
    "${MOONRAKER_ENV}"/bin/pip install -r "${DANYBOT_API_DIR}/requirements.txt"
  fi

  ### required due to https://github.com/Arksine/moonraker/issues/349
  # install_moonraker_polkit || true

  ok_msg "Update complete!"
  do_action_service "restart" "danybot_api"
}