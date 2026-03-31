#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# create-arr-users.sh
#
# Creates:
#   - Shared group (default: media, GID 2000)
#   - Dedicated system users for each service (qbittorrent, prowlarr, sonarr, radarr, bazarr, seerr)
#   - Local config directories under CONFIG_ROOT
#   - Local downloads directory under DOWNLOADS_ROOT
#
# SSHFS NOTE:
#   MEDIA_ROOT is assumed to be an sshfs mount (e.g. /mnt/ardbeg).
#   This script will NOT create subfolders under MEDIA_ROOT and will NOT chown/chmod
#   anything inside MEDIA_ROOT (remote permissions + sshfs mount options control that).
#   It only verifies that MEDIA_ROOT exists as a directory.
# ==============================================================================

# --- Paths (override via env vars when running the script) ---
CONFIG_ROOT="${CONFIG_ROOT:-/opt/arr/config}"

# Local fast storage for active torrent downloads
DOWNLOADS_ROOT="${DOWNLOADS_ROOT:-/srv/downloads}"

# Remote media storage mount point (sshfs)
MEDIA_ROOT="${MEDIA_ROOT:-/mnt/ardbeg}"

# Shared group used by all services (matches MEDIA_GID in .env)
MEDIA_GROUP="${MEDIA_GROUP:-media}"
MEDIA_GID="${MEDIA_GID:-2000}"

# Service users (override by editing here if desired)
declare -A USERS=(
  [qbittorrent]=2100
  [prowlarr]=2101
  [sonarr]=2102
  [radarr]=2103
  [bazarr]=2104
  [seerr]=2105
)

ensure_group() {
  local group="$1" gid="$2"
  if getent group "$group" >/dev/null 2>&1; then
    echo "Group '$group' already exists."
  else
    echo "Creating group '$group' (GID=$gid)..."
    groupadd --gid "$gid" "$group"
  fi
}

ensure_user() {
  local user="$1" uid="$2" group="$3"
  if id "$user" >/dev/null 2>&1; then
    echo "User '$user' already exists."
  else
    echo "Creating system user '$user' (UID=$uid, primary group=$group)..."
    useradd \
      --system \
      --uid "$uid" \
      --gid "$group" \
      --home-dir "/var/lib/$user" \
      --create-home \
      --shell /usr/sbin/nologin \
      "$user"
  fi
}

add_to_group() {
  local user="$1" group="$2"
  echo "Adding '$user' to supplemental group '$group'..."
  usermod -aG "$group" "$user"
}

make_dirs() {
  echo "Creating local directories..."

  # Config directories (local)
  mkdir -p \
    "$CONFIG_ROOT/qbittorrent" \
    "$CONFIG_ROOT/prowlarr" \
    "$CONFIG_ROOT/sonarr" \
    "$CONFIG_ROOT/radarr" \
    "$CONFIG_ROOT/bazarr" \
    "$CONFIG_ROOT/seerr"

  # Local downloads directory (local)
  mkdir -p "$DOWNLOADS_ROOT"

  # Remote media mountpoint: verify only (do not create/chown/chmod inside)
  if [ ! -d "$MEDIA_ROOT" ]; then
    echo "ERROR: MEDIA_ROOT '$MEDIA_ROOT' does not exist as a directory."
    echo "       If this is an sshfs mount, ensure it is mounted before running this script."
    exit 1
  fi
}

set_permissions() {
  echo "Setting ownership and permissions (local only)..."

  # Config dirs: owned by each service user, group=MEDIA_GROUP
  # 2775 -> setgid on directories + group writable, so group inheritance works
  for svc in "${!USERS[@]}"; do
    chown -R "${svc}:${MEDIA_GROUP}" "$CONFIG_ROOT/$svc"
    chmod -R 2775 "$CONFIG_ROOT/$svc"
  done

  # Local downloads: group-writable and setgid so new files inherit MEDIA_GROUP
  chown -R "root:${MEDIA_GROUP}" "$DOWNLOADS_ROOT"
  chmod -R 2775 "$DOWNLOADS_ROOT"

  echo "NOTE: Skipping permission changes for MEDIA_ROOT ('$MEDIA_ROOT')"
  echo "      because it is assumed to be sshfs-controlled (remote perms + mount options)."

  echo "Done."
}

main() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)."
    exit 1
  fi

  ensure_group "$MEDIA_GROUP" "$MEDIA_GID"

  for svc in "${!USERS[@]}"; do
    ensure_user "$svc" "${USERS[$svc]}" "$MEDIA_GROUP"
    add_to_group "$svc" "$MEDIA_GROUP"
  done

  make_dirs
  set_permissions

  echo
  echo "Summary:"
  echo "  CONFIG_ROOT=$CONFIG_ROOT"
  echo "  DOWNLOADS_ROOT=$DOWNLOADS_ROOT"
  echo "  MEDIA_ROOT=$MEDIA_ROOT (verified only)"
  echo "  MEDIA_GROUP=$MEDIA_GROUP (GID=$MEDIA_GID)"
  for svc in "${!USERS[@]}"; do
    echo "  $svc: UID=${USERS[$svc]}"
  done

  echo
  echo "Quick checks you can run:"
  echo "  ls -ld \"$DOWNLOADS_ROOT\""
  echo "  ls -ld \"$CONFIG_ROOT\"/*"
  echo "  sudo -u qbittorrent touch \"$DOWNLOADS_ROOT\"/.perm_test && rm \"$DOWNLOADS_ROOT\"/.perm_test"
}

main "$@"
