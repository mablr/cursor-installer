#!/usr/bin/env bash

set -euo pipefail

# Constants
readonly APPIMAGE_DIR="$HOME/.AppImage"
readonly ICON_DIR="$HOME/.local/share/icons"
readonly USER_DESKTOP_FILE="$HOME/Desktop/cursor.desktop"
readonly APPLICATION_DESKTOP_FILE="$HOME/.local/share/applications/cursor.desktop"
readonly CLI_COMMAND="/usr/local/bin/cursor"
readonly API_URL="https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=latest"
readonly ICON_URL="https://raw.githubusercontent.com/mablr/cursor-installer/refs/heads/master/cursor-icon.svg"

# Variables
local_hash=""
remote_hash=""
download_url=""

# Set log level (0=error, 1=warn, 2=info)
LOG_LEVEL=2

# Function Definitions
log() {
  local level=$1
  local msg=$2
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

  case $level in
    0) [[ $LOG_LEVEL -ge 0 ]] && echo -e "[$timestamp] ERROR: $msg" ;;
    1) [[ $LOG_LEVEL -ge 1 ]] && echo -e "[$timestamp] WARNING: $msg" ;;
    2) [[ $LOG_LEVEL -ge 2 ]] && echo -e "[$timestamp] INFO: $msg" ;;
  esac
}

validate_os() {
  log 2 "Checking system compatibility..."
  if ! command -v apt &> /dev/null; then
    os_name=$(grep -i '^NAME=' /etc/os-release | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "Unknown")
    log 0 "This script requires the APT package manager. Detected: $os_name. Exiting..."
    exit 1
  fi
  os_name=$(grep -i '^NAME=' /etc/os-release | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "Debian-based")
  log 2 "Detected $os_name with APT package manager. System is compatible."
}

check_dependencies() {
  log 2 "Checking dependencies..."
  local missing=()
  
  local deps=(
    "curl"
    "jq"
    "xxd"
  )
  
  for dep in "${deps[@]}"; do
    if ! dpkg -s "$dep" > /dev/null 2>&1; then
      missing+=("$dep")
    fi
  done

  if ! dpkg -s "libfuse2" > /dev/null 2>&1 && ! dpkg -s "libfuse2t64" > /dev/null 2>&1; then
    missing+=("libfuse2")
  fi
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    log 1 "Installing missing dependencies: ${missing[*]}"
    sudo apt update -y && sudo apt install -y "${missing[@]}"
  fi
  
  log 2 "All dependencies are installed."
}

find_remote_version() {
  log 2 "Looking for the latest version online..."
  local api_response
  local headers

  api_response=$(timeout "5" curl -s -L "$API_URL")
  if [[ $? -ne 0 ]]; then
    log 0 "Failed to fetch data from the API server. Check your internet connection."
    return 1
  fi
  
  download_url=$(echo "$api_response" | jq -r '.downloadUrl')
  if [[ -z "$download_url" || "$download_url" == "null" ]]; then
    log 0 "Failed to extract download URL from API response. Response: $api_response"
    return 1
  fi
  
  headers=$(timeout "5" curl -s -L -I "$download_url")
  if [[ -z "$headers" ]]; then
    log 0 "Failed to fetch file details from the download server."
    return 1
  fi
  
  remote_hash=$(echo "$headers" | grep -i 'etag:' | sed 's/etag: //;s/"//g' | tr -d '\r\n' || echo "unknown")
  
  log 2 "Latest version hash: $remote_hash"
  return 0
}

calculate_etag() {
  local chunk_size=5 # Cursor appimage uses 5MB chunks 
  local file_size=$(du -b "$1" | cut -f 1)
  local chunks=$((file_size / (chunk_size * 1024 * 1024)))
  
  if [[ $((file_size % (chunk_size * 1024 * 1024))) -gt 0 ]]; then 
    chunks=$((chunks + 1))
  fi
  
  local tmp_file=$(mktemp -t cursor-local-etag.XXXXXXXXXXXXX)
  for (( chunk=0; chunk<$chunks; chunk++ )); do
    dd bs=1M count=$chunk_size skip=$((chunk_size * chunk)) if="$1" 2> /dev/null | md5sum >> $tmp_file
  done
  
  local etag=$(echo "$(xxd -r -p "$tmp_file" | md5sum | cut -f 1 -d ' ')"-$chunks)
  rm "$tmp_file"
  echo "$etag"
}

find_local_version() {
  if [[ -f "$APPIMAGE_DIR/Cursor.AppImage" ]]; then
    local_hash=$(calculate_etag "$APPIMAGE_DIR/Cursor.AppImage")
    log 2 "Local version hash: $local_hash"
    return 0
  else
    log 2 "No local version found in $APPIMAGE_DIR"
    return 1
  fi
}

download_logo() {
  log 2 "Downloading Cursor logo..."
  mkdir -p "$ICON_DIR"
  
  if curl -s -o "$ICON_DIR/cursor-icon.svg" "$ICON_URL"; then
    log 2 "Logo successfully downloaded to: $ICON_DIR/cursor-icon.svg"
    return 0
  else
    log 0 "Failed to download the logo. Please check your connection."
    return 1
  fi
}

download_appimage() {
  mkdir -p "$APPIMAGE_DIR"

  log 2 "Starting the download of the latest version..."
  local cursor_path="$APPIMAGE_DIR/Cursor.AppImage"
  
  if [[ -z "$download_url" ]]; then
    log 0 "Download URL is empty. Please fetch the remote version first."
    return 1
  fi
  
  log 2 "Downloading AppImage to $cursor_path"
  
  if curl -L --progress-bar -o "$cursor_path" "$download_url"; then
    log 2 "Download completed successfully"
  else
    log 0 "AppImage download failed."
    return 1
  fi
  
  log 2 "Adjusting permissions for the AppImage..."
  if chmod +x "$cursor_path"; then
    log 2 "Permissions updated for the new AppImage."
  else
    log 0 "Failed to set executable permissions for $cursor_path"
    return 1
  fi
  return 0
}

setup_launchers() {
  log 2 "Creating launchers for Cursor..."
  
  for launcher_path in "$USER_DESKTOP_FILE" "$APPLICATION_DESKTOP_FILE"; do
    local dir_path=$(dirname "$launcher_path")
    [[ ! -d "$dir_path" ]] && mkdir -p "$dir_path"
    
    cat > "$launcher_path" << EOF
[Desktop Entry]
Type=Application
Name=Cursor
GenericName=Intelligent, fast, and familiar, Cursor is the best way to code with AI.
Exec=$APPIMAGE_DIR/Cursor.AppImage --no-sandbox
Icon=$ICON_DIR/cursor-icon.svg
Categories=Utility;Development
StartupWMClass=Cursor
Terminal=false
Comment=Cursor is an AI-first coding environment for software development.
Keywords=cursor;ai;code;editor;ide;artificial;intelligence;learning;programming;developer;development;software;engineering;productivity;vscode;sublime;coding;gpt;openai;copilot;
MimeType=x-scheme-handler/cursor;
EOF
    
    if chmod +x "$launcher_path"; then
      log 2 "Launcher set as executable: $launcher_path"
    else
      log 1 "Failed to set permissions for $launcher_path"
    fi
    
    # Make launcher trusted if gio is available
    if command -v gio > /dev/null 2>&1; then
      if gio set "$launcher_path" "metadata::trusted" true 2>/dev/null; then
        log 2 "Launcher marked as trusted: $launcher_path"
      else
        log 1 "Failed to mark $launcher_path as trusted"
      fi
    fi
  done
  
  log 2 "Launchers setup completed"
  return 0
}

add_cli_command() {
  log 2 "Adding the 'cursor' command to your system..."
  
  local script_content="#!/bin/bash

APPIMAGE_PATH=\"$APPIMAGE_DIR/Cursor.AppImage\"

if [[ ! -f \"\$APPIMAGE_PATH\" ]]; then
   echo \"Error: Cursor AppImage not found at \$APPIMAGE_PATH\" >&2;
   exit 1;
fi

\"\$APPIMAGE_PATH\" --no-sandbox \"\$@\" &> /dev/null &
"
  
  if echo "$script_content" | sudo tee "$CLI_COMMAND" > /dev/null; then
    if sudo chmod +x "$CLI_COMMAND"; then
      log 2 "CLI command 'cursor' successfully installed."
      return 0
    else
      log 0 "Failed to set permissions for $CLI_COMMAND"
      return 1
    fi
  else
    log 0 "Failed to create CLI command."
    return 1
  fi
}

remove_icon() {
  log 2 "Removing Cursor icon..."
  if [[ -f "$ICON_DIR/cursor-icon.svg" ]]; then
    if rm -f "$ICON_DIR/cursor-icon.svg"; then
      log 2 "Icon removed successfully."
    else
      log 0 "Failed to remove icon file."
      return 1
    fi
  else
    log 2 "Icon file not found. Skipping."
  fi
  return 0
}

remove_launchers() {
  log 2 "Removing desktop files..."
  local result=0
  
  if [[ -f "$USER_DESKTOP_FILE" ]]; then
    if rm -f "$USER_DESKTOP_FILE"; then
      log 2 "Desktop file removed: $USER_DESKTOP_FILE"
    else
      log 0 "Failed to remove desktop file: $USER_DESKTOP_FILE"
      result=1
    fi
  else
    log 2 "Desktop file not found: $USER_DESKTOP_FILE. Skipping."
  fi
  
  if [[ -f "$APPLICATION_DESKTOP_FILE" ]]; then
    if rm -f "$APPLICATION_DESKTOP_FILE"; then
      log 2 "Application desktop file removed: $APPLICATION_DESKTOP_FILE"
    else
      log 0 "Failed to remove application desktop file: $APPLICATION_DESKTOP_FILE"
      result=1
    fi
  else
    log 2 "Application desktop file not found: $APPLICATION_DESKTOP_FILE. Skipping."
  fi
  
  return $result
}

remove_cli_command() {
  log 2 "Removing 'cursor' command..."
  if [[ -f "$CLI_COMMAND" ]]; then
    if sudo rm -f "$CLI_COMMAND"; then
      log 2 "CLI command removed successfully."
    else
      log 0 "Failed to remove CLI command."
      return 1
    fi
  else
    log 2 "CLI command not found. Skipping."
  fi
  return 0
}

remove_appimages() {
  log 2 "Removing Cursor AppImages..."
  local cursor_appimages=$(find "$APPIMAGE_DIR" -maxdepth 1 -type f -name 'Cursor*.AppImage*' 2>/dev/null)
  
  if [[ -z "$cursor_appimages" ]]; then
    log 2 "No Cursor AppImages found in $APPIMAGE_DIR"
    return 0
  fi
  
  local count=0
  while IFS= read -r appimage; do
    if rm -f "$appimage"; then
      log 2 "Removed: $appimage"
      ((count++))
    else
      log 0 "Failed to remove: $appimage"
    fi
  done <<< "$cursor_appimages"
  
  log 2 "Removed $count Cursor AppImage(s)."
  return 0
}

uninstall_cursor() {
  local purge=$1
  log 2 "Uninstalling Cursor..."
  
  remove_icon
  remove_launchers
  remove_cli_command
  
  if [[ "$purge" == true ]]; then
    remove_appimages
  fi
  
  log 2 "Cursor has been uninstalled successfully!"
  return 0
}

print_usage() {
  cat << EOF
Usage: $0 [OPTIONS]

A command-line installer for Cursor AppImage on Debian/Ubuntu based Linux distributions.

Options:
  -a, --all             All-in-one Cursor installation (Recommended)

  -f, --fetch           Only fetch latest Cursor AppImage 
  -c, --configure       Configure desktop launcher and CLI

  -s, --status          Check Cursor installation status

  -r, --remove          Uninstall Cursor (remove icon, desktop launcher, and CLI command)
  -p, --remove-purge    Uninstall Cursor and purge all AppImages

  -h, --help            Show help message
  -q, --quiet           Show only errors and warnings

Report bugs to: https://github.com/mablr/cursor-installer/issues
EOF
}

print_status() {
  log 2 "Checking Cursor installation status..."
  
  # Check if Cursor is installed
  if ! find_local_version; then
    echo "Cursor is not installed."
    echo "Run '$0 --all' to install Cursor."
    return 1
  fi
  
  # Show basic installation info
  echo "Cursor is installed at $APPIMAGE_DIR/Cursor.AppImage"
  
  # Initialize configuration status flag
  local config_needs_update=false
  
  # Check launchers (desktop and application)
  echo -n "  Launcher: "
  
  if [[ ! -f "$USER_DESKTOP_FILE" || ! -f "$APPLICATION_DESKTOP_FILE" ]]; then
    echo "No [NEEDS CONFIGURATION]"
    config_needs_update=true
  else
    local desktop_exec=$(grep -oP '^Exec=\K.*AppImage' "$USER_DESKTOP_FILE" 2>/dev/null)
    local application_exec=$(grep -oP '^Exec=\K.*AppImage' "$APPLICATION_DESKTOP_FILE" 2>/dev/null)
    if [[ -n "$desktop_exec" && "$desktop_exec" == "$APPIMAGE_DIR/Cursor.AppImage" && -n "$application_exec" && "$application_exec" == "$APPIMAGE_DIR/Cursor.AppImage" ]]; then
      echo "Yes [VALID]"
    else
      echo "Yes [NEEDS RECONFIGURATION]"
      config_needs_update=true
    fi
  fi
  
  # Check CLI command
  echo -n "  CLI command: "
  
  if ! command -v cursor &> /dev/null; then
    echo "No [NEEDS CONFIGURATION]"
    config_needs_update=true
  else
    local cli_path=$(grep -oP 'APPIMAGE_PATH="\K[^"]*' "$(which cursor)" 2>/dev/null)
    if [[ -n "$cli_path" && "$cli_path" == "$APPIMAGE_DIR/Cursor.AppImage" ]]; then
      echo "Yes ($(which cursor)) [VALID]"
    else
      echo "Yes ($(which cursor)) [NEEDS RECONFIGURATION]"
      config_needs_update=true
    fi
  fi

  # Show recommendation if any configuration needs update
  if [[ "$config_needs_update" == true ]]; then
    echo ""
    echo "Some configuration needs to be updated. Run '$0 --configure' to fix."
  fi
  
  return 0
}

# Main logic
main() {
  if [[ $# -eq 0 ]]; then
    print_usage
    exit 0
  fi
  
  # Validate operating system
  validate_os

  local do_fetch=false
  local do_logo=false
  local do_desktop=false
  local do_cli=false
  local do_status=false
  local do_remove=false
  local do_purge=false
  
  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        print_usage
        exit 0
        ;;
      -a|--all)
        do_fetch=true
        do_logo=true
        do_desktop=true
        do_cli=true
        shift
        ;;
      -f|--fetch)
        do_fetch=true
        shift
        ;;
      -c|--configure)
        do_logo=true
        do_desktop=true
        do_cli=true
        shift
        ;;
      -s|--status)
        do_status=true
        shift
        ;;
      -r|--remove)
        do_remove=true
        shift
        ;;
      -p|--remove-purge)
        do_remove=true
        do_purge=true
        shift
        ;;
      -q|--quiet)
        LOG_LEVEL=1
        shift
        ;;
      *)
        echo "Unknown option: $1"
        print_usage
        exit 1
        ;;
    esac
  done
  
  # Check status if requested
  if [[ "$do_status" == true ]]; then
    print_status
    exit $?
  fi
  
  # Handle uninstall/purge if requested
  if [[ "$do_remove" == true ]]; then
    uninstall_cursor "$do_purge"
    exit $?
  fi
  
  # Fetch remote version if requested
  if [[ "$do_fetch" == true ]]; then
    # Check and install dependencies
    check_dependencies
    
    find_remote_version || exit 1
  
    # Download if requested
    if ! find_local_version || [[ "$local_hash" != "$remote_hash" ]]; then
      download_appimage || exit 1
    else
      log 2 "Latest version already downloaded. No need to download again."
    fi
  fi
  
  # If we need to configure but have no local version
  if [[ "$do_desktop" == true || "$do_cli" == true || "$do_logo" == true ]]; then
    if ! find_local_version; then
      log 0 "No local Cursor AppImage found. Use --fetch to download."
      exit 1
    fi
  fi
  
  # Download logo if needed
  if [[ "$do_logo" == true ]]; then
    download_logo
  fi
  
  # Set up desktop entries if requested
  if [[ "$do_desktop" == true ]]; then
    setup_launchers
  fi
  
  # Add CLI command if requested
  if [[ "$do_cli" == true ]]; then
    add_cli_command
  fi
  
  log 2 "Cursor setup script completed successfully!"
  return 0
}

main "$@"
