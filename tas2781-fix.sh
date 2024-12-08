#!/bin/bash

set -euo pipefail

# This script is used to fix the audio problems on Legion Pro 7 16IRX8H.
# This is a combination of solutions from https://forums.lenovo.com/t5/Ubuntu/Ubuntu-and-legion-pro-7-16IRX8H-audio-issues/m-p/5210709

SERVICE_NAME="tas2781-fix.service"
SCRIPT_PATH="/usr/local/bin/tas2781-fix"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
USER_SERVICE_PATH="/etc/systemd/user/$SERVICE_NAME"
POLKIT_RULES_PATH="/etc/polkit-1/rules.d/10-tas2781-fix-$(id -u).rules"
DISABLE_POWERSAVE_MODPROBE="/etc/modprobe.d/audio_disable_powersave.conf"
DISABLE_PIPEWIRE_SUSPEND_CONF="/etc/wireplumber/wireplumber.conf.d/51-disable-suspension.conf"
__SUPPRESS_UNINSTALL_MESSAGE=${__SUPPRESS_UNINSTALL_MESSAGE:-}

uninstall() {
  if [ "$(id -u)" -eq 0 ]; then
    echo "This script must not be run as root." >&2
    exit 1
  fi
  
  local service_changes_made=0

  sudo true

  if [ "$0" != "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
    # Call the uninstall function from the installed script. This allows older versions to uninstall themselves.
    __SUPPRESS_UNINSTALL_MESSAGE=1 "$SCRIPT_PATH" --uninstall
    return 0
  fi

  # stop running units if they exist
  if systemctl is-active --user --quiet $SERVICE_NAME; then
    echo "Stopping tas2781-fix service."
    systemctl --user stop $SERVICE_NAME
  fi

  if systemctl is-active --quiet $SERVICE_NAME; then
    echo "Stopping tas2781-fix execution unit."
    sudo systemctl stop $SERVICE_NAME
  fi

  # disable running units if they exist
  if systemctl is-enabled --user --quiet $SERVICE_NAME; then
    echo "Disabling tas2781-fix service."
    systemctl --user disable $SERVICE_NAME
  fi

  if [ -f $SERVICE_PATH ]; then
    echo "Removing tas2781-fix execution unit at $SERVICE_PATH."
    service_changes_made=1
    sudo rm -f "$SERVICE_PATH"
  fi

  if [ -f "$USER_SERVICE_PATH" ]; then
    echo "Removing tas2781-fix service at $USER_SERVICE_PATH."
    service_changes_made=1
    sudo rm -f "$USER_SERVICE_PATH"
  fi

  if [ -f "$DISABLE_POWERSAVE_MODPROBE" ]; then
    echo "Removing kernel module configuration at $DISABLE_POWERSAVE_MODPROBE."
    sudo rm -f "$DISABLE_POWERSAVE_MODPROBE"
  fi

  if [ -f "$DISABLE_PIPEWIRE_SUSPEND_CONF" ]; then
    echo "Removing PipeWire configuration at $DISABLE_PIPEWIRE_SUSPEND_CONF."
    sudo rm -f "$DISABLE_PIPEWIRE_SUSPEND_CONF"
  fi

  
  if sudo bash -c '[ -f '"'$POLKIT_RULES_PATH'"' ]'; then
    echo "Removing polkit rule at $POLKIT_RULES_PATH."
    sudo rm -f "$POLKIT_RULES_PATH"
  fi

  if [ "$service_changes_made" -eq 1 ]; then
    echo "Reloading systemd daemon."
    sudo systemctl daemon-reload
    systemctl --user daemon-reload
  fi

  if [ -f "$SCRIPT_PATH" ]; then
    echo "Removing script at $SCRIPT_PATH."
    sudo rm -f "$SCRIPT_PATH"
  fi
}

install() {
  if [ "$(id -u)" -eq 0 ]; then
    echo "This script must not be run as root." >&2
    exit 1
  fi

  sudo true
  uninstall

  if [ "$0" != "$SCRIPT_PATH" ]; then
    echo "Copying script to $SCRIPT_PATH."
    sudo cp "$0" "$SCRIPT_PATH"
    sudo chmod 0755 "$SCRIPT_PATH"
  fi

  sudo mkdir -p "$(dirname "$POLKIT_RULES_PATH")"
  sudo mkdir -p "$(dirname "$SERVICE_PATH")"
  sudo mkdir -p "$(dirname "$USER_SERVICE_PATH")"
  sudo mkdir -p "$(dirname "$DISABLE_POWERSAVE_MODPROBE")"
  sudo mkdir -p "$(dirname "$DISABLE_PIPEWIRE_SUSPEND_CONF")"

  echo "Creating polkit rule at $POLKIT_RULES_PATH."
  sudo tee "$POLKIT_RULES_PATH" >/dev/null <<EOF
polkit.addRule(function(action, subject) {
  if (action.id !== "org.freedesktop.systemd1.manage-units") return;
  if (action.lookup("unit") !== "$SERVICE_NAME") return;
  var cgroup = polkit.spawn(["cat","/proc/"+subject.pid+"/cgroup"]).trim();
  if (cgroup == "0::/user.slice/user-$(id -u).slice/user@$(id -u).service/app.slice/$SERVICE_NAME") return polkit.Result.YES;  
});
EOF

  echo "Creating tas2781-fix execution unit at $SERVICE_PATH."
  sudo tee "$SERVICE_PATH" >/dev/null <<EOF
[Unit]
Description=Run the tas2781-fix script when triggered

[Service]
ExecStart=$SCRIPT_PATH --execute
Type=oneshot
TimeoutSec=60
RemainAfterExit=yes
EOF

  echo "Creating tas2781-fix service at $USER_SERVICE_PATH."
  sudo tee "$USER_SERVICE_PATH" >/dev/null <<EOF
[Unit]
Description=Trigger the tas2781-fix script on login and resume
After=pipewire.service
Before=wireplumber.service
Requires=pipewire.service

[Service]
ExecStart=$SCRIPT_PATH --start
Restart=no
Type=exec

[Install]
WantedBy=pipewire.service
EOF

  echo "Creating kernel module configuration at $DISABLE_POWERSAVE_MODPROBE."
  sudo tee "$DISABLE_POWERSAVE_MODPROBE" >/dev/null <<EOF
options snd_hda_intel power_save=0
options snd_hda_intel power_save_controller=N
blacklist snd_soc_avs
EOF

  echo "Creating PipeWire configuration at $DISABLE_PIPEWIRE_SUSPEND_CONF."
  sudo tee "$DISABLE_PIPEWIRE_SUSPEND_CONF" >/dev/null <<EOF
monitor.alsa.rules = [
  {
    matches = [
      {
        # Matches all sources
        node.name = "~alsa_input.*"
      },
      {
        # Matches all sinks
        node.name = "~alsa_output.*"
      }
    ]
    actions = {
      update-props = {
        session.suspend-timeout-seconds = 0
      }
    }
  }
]
# bluetooth devices
monitor.bluez.rules = [
  {
    matches = [
      {
        # Matches all sources
        node.name = "~bluez_input.*"
      },
      {
        # Matches all sinks
        node.name = "~bluez_output.*"
      }
    ]
    actions = {
      update-props = {
        session.suspend-timeout-seconds = 0
      }
    }
  }
]
EOF

  echo "Reloading systemd daemon."
  sudo systemctl daemon-reload
  systemctl --user daemon-reload

  echo "Enabling tas2781-fix service."
  systemctl --user enable --now $SERVICE_NAME
}

find_i2c_bus() {
  find /sys/bus/i2c/devices/i2c-*/i2c-TIAS2781\:00 -maxdepth 0 -print -quit | cut -f6 -d/ | cut -f2 -d-
}

find_i2c_addresses() {
  local i2c_bus="$1"
  local current_value=0
  
  i2cdetect -y -r $i2c_bus | tail -n +2 | while read -r line; do 
    line=${line: -48:48}
    for ((i=0; i<${#line}; i+=3)); do
        local substring=${line: $i+1:2}
        if [[ "$substring" == "UU" || "$substring" =~ [0-9a-fA-F]{2} ]]; then
            echo $current_value
        fi
        ((current_value+=1))
    done
  done
}

execute_fix() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "You must run this script as root." >&2
    exit 1
  fi

  local power_save_path="/sys/module/snd_hda_intel/parameters/power_save"
  local power_control_path="/sys/bus/i2c/drivers/tas2781-hda/i2c-TIAS2781:00/power/control"
  local i2c_bus=$(find_i2c_bus)
  local i2c_addr=($(find_i2c_addresses "$i2c_bus"))

  local count=0
  for value in ${i2c_addr[@]}; do
    local balance_index=$((count % 2))

    # TAS2781 initialization
    # Data sheet: https://www.ti.com/lit/ds/symlink/tas2781.pdf

    i2cset -f -y $i2c_bus $value 0x00 0x00 # Page 0x00
    i2cset -f -y $i2c_bus $value 0x7f 0x00 # Book 0x00
    i2cset -f -y $i2c_bus $value 0x01 0x01 # Software Reset

    i2cset -f -y $i2c_bus $value 0x0e 0xc4 0x40 i # TDM TX voltage sense enable with slot 4, curent sense enable with slot 0
    i2cset -f -y $i2c_bus $value 0x5c 0xd9 # CLK_PWRUD=1, DIS_CLK_HALT=0, CLK_HALT_TIMER=011, IRQZ_CLR=0, IRQZ_CFG=3
    i2cset -f -y $i2c_bus $value 0x60 0x10 # SBCLK_FS_RATIO=2
    
    if [ $balance_index -eq 0 ]; then # Left/right channel configuration
        i2cset -f -y $i2c_bus $value 0x0a 0x1e
    else
        i2cset -f -y $i2c_bus $value 0x0a 0x2e
    fi

    i2cset -f -y $i2c_bus $value 0x0d 0x01 # TX_KEEPCY=0, TX_KEEPLN=0, TX_KEEPEN=0, TX_FILL=0, TX_OFFSET=000, TX_EDGE=1
    i2cset -f -y $i2c_bus $value 0x16 0x40 # AUDIO_SLEN=0, AUDIO_TX=0, AUDIO_SLOT=2

    i2cset -f -y $i2c_bus $value 0x00 0x01 # Page 0x01
    i2cset -f -y $i2c_bus $value 0x17 0xc8 # SARBurstMask=0

    i2cset -f -y $i2c_bus $value 0x00 0x04 # Page 0x04
    i2cset -f -y $i2c_bus $value 0x30 0x00 0x00 0x00 0x01 i # Merge Limiter and Thermal Foldback gains

    i2cset -f -y $i2c_bus $value 0x00 0x08 # Page 0x08
    i2cset -f -y $i2c_bus $value 0x18 0x00 0x00 0x00 0x00 i # 0dB volume
    i2cset -f -y $i2c_bus $value 0x28 0x40 0x00 0x00 0x00 i # Unmute

    i2cset -f -y $i2c_bus $value 0x00 0x0a # Page 0x0a
    i2cset -f -y $i2c_bus $value 0x48 0x00 0x00 0x00 0x00 i # 0dB volume
    i2cset -f -y $i2c_bus $value 0x58 0x40 0x00 0x00 0x00 i # Unmute

    i2cset -f -y $i2c_bus $value 0x00 0x00 # Page 0x00
    i2cset -f -y $i2c_bus $value 0x02 0x00 # Play audio, power up with playback, IV enabled

    count=$((count+1))

  done

  until [ -e "$power_save_path" ] && [ -e "$power_control_path" ]; do
    sleep 1
  done

  # Disable snd_hda_intel power saving
  printf "0" > "$power_save_path"

  # Disable runtime suspend/resume for tas2781
  printf "on" > "$power_control_path"
}

run_fix_service() {
  local unarray='.[]'
  local state_changed='select(.info["change-mask"]|index("state"))'
  local props_changed='select(.info["change-mask"]|index("props"))'
  local sink='select(.info.props["media.class"]=="Audio/Sink")'
  local snd_hda_intel='select(.info.props["alsa.driver_name"]=="snd_hda_intel")'
  local alsa_card_name='select(.info.props["alsa.card_name"]=="HDA Intel PCH")'

  pw-dump -m | stdbuf -oL jq -cM "$unarray|$snd_hda_intel|$alsa_card_name|$sink|$state_changed|$props_changed|1" | while read; do
    systemctl restart $SERVICE_NAME
  done
}

check-dependencies() {
  if ! command -v i2cset &>/dev/null; then
    echo "The i2c-tools package is required to run this script." >&2
    exit 1
  fi
  
  if ! command -v jq &>/dev/null; then
    echo "The jq package is required to run this script." >&2
    exit 1
  fi

  if ! command -v pw-dump &>/dev/null; then
    echo "The pipewire package is required to run this script." >&2
    exit 1
  fi

  if ! command -v pkexec &>/dev/null; then
    echo "The polkit package is required to run this script." >&2
    exit 1
  fi
}

print_usage() {
  echo "Usage: $0 [OPTION]"
  echo "Options:"
  echo "  --install    Install the tas2781-fix script and enable the service."
  echo "  --uninstall  Uninstall the tas2781-fix script and disable the service."
  echo "  --execute    Execute the tas2781-fix script."
  echo "  --start      Start the tas2781-fix service."
  echo "  --help       Display this help message."
}

parse_args() {
  if [ "$#" -ne 1 ]; then
    print_usage
    exit 1
  fi

  check-dependencies

  case "$1" in
    --execute)
      execute_fix
      exit 0
      ;;
    --start)
      run_fix_service
      exit 0
      ;;
    --install)
      install
      echo "tas2781-fix has been installed successfully."
      echo "Please reboot your system to apply the changes."
      exit 0
      ;;
    --uninstall)
      uninstall
      
      if [ -z "$__SUPPRESS_UNINSTALL_MESSAGE" ]; then
        echo "tas2781-fix has been uninstalled successfully."
        echo "Please reboot your system to apply the changes."
      fi

      exit 0
      ;;
    --help)
      print_usage
      exit 0
      ;;
    *)
      echo "Invalid argument: $1" >&2
      print_usage
      
      exit 1
      ;;
  esac
}

parse_args "$@"
