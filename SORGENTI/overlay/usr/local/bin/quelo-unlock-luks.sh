#!/bin/bash
# Sblocco LUKS con passphrase fornita dall'utente (nessun brute-force).

LUKS_MAPPER_PREFIX="quelo-luks"
LUKS_MOUNT_BASE="/mnt/quelo-luks-open"

quelo_unlock_luks_collect() {
  local disk="$1" part

  LUKS_PARTS=()
  LUKS_LABELS=()

  while IFS= read -r part; do
    [[ -n "${part}" ]] || continue
    quelo_live_is_medium_partition "${part}" && continue
    command -v cryptsetup >/dev/null 2>&1 || continue
    cryptsetup isLuks "${part}" >/dev/null 2>&1 || continue
    LUKS_PARTS+=("${part}")
    LUKS_LABELS+=("${part} $(lsblk -no SIZE "${part}" 2>/dev/null | head -1)")
  done < <(quelo_disk_enum_partitions "${disk}")

  ((${#LUKS_PARTS[@]} > 0))
}

quelo_unlock_luks_read_pass() {
  local prompt="$1" pass

  quelo_unlock_tty "${C_AMBER}  ${prompt}${C_RESET}"
  if ! IFS= read -r -s pass </dev/tty 2>/dev/null; then
    return 1
  fi
  quelo_unlock_tty $'\n'
  [[ -n "${pass}" ]] || return 1
  printf '%s' "${pass}"
}

quelo_unlock_luks_mount_mapper() {
  local mapper="$1" mp fstype

  mp="${LUKS_MOUNT_BASE}/${mapper##*/}"
  mkdir -p "${mp}"
  fstype="$(blkid -o value -s TYPE "/dev/mapper/${mapper}" 2>/dev/null)" || fstype=""
  fstype="$(quelo_fs_normalize_type "${fstype}")"

  case "${fstype}" in
    ntfs)
      mount -t ntfs-3g -o rw "/dev/mapper/${mapper}" "${mp}" 2>/dev/null \
        || mount -o rw "/dev/mapper/${mapper}" "${mp}" 2>/dev/null
      ;;
    ext2|ext3|ext4|btrfs|xfs|vfat|exfat)
      mount -o rw "/dev/mapper/${mapper}" "${mp}" 2>/dev/null
      ;;
    *)
      mount -o ro "/dev/mapper/${mapper}" "${mp}" 2>/dev/null
      ;;
  esac

  if mountpoint -q "${mp}" 2>/dev/null; then
    printf '%s' "${mp}"
    return 0
  fi
  return 1
}

quelo_unlock_luks_menu() {
  local disk="$1" i num idx choice part mapper pass mp rc=0

  if ! command -v cryptsetup >/dev/null 2>&1; then
    quelo_unlock_ttyln "  $(quelo_unlock_t luks_no_tool)"
    quelo_unlock_pause
    return 1
  fi

  if ! quelo_unlock_luks_collect "${disk}"; then
    quelo_unlock_ttyln "  $(quelo_unlock_t luks_no_part)"
    quelo_unlock_pause
    return 1
  fi

  if ((${#LUKS_PARTS[@]} > 1)); then
    quelo_unlock_ttyln ""
    quelo_unlock_ttyln "${C_AMBER}  $(quelo_unlock_t luks_pick_part)${C_RESET}"
    for i in "${!LUKS_PARTS[@]}"; do
      num=$((i + 1))
      quelo_unlock_ttyln "  ${C_GREEN}${num})${C_RESET} ${LUKS_LABELS[$i]}"
    done
    quelo_unlock_ttyln ""
    quelo_unlock_tty "${C_AMBER}  $(quelo_unlock_t prompt)${C_RESET}"
    quelo_unlock_read_choice || return 1
    choice="${DISK_CHOICE}"
    idx=$((choice - 1))
    ((idx >= 0 && idx < ${#LUKS_PARTS[@]})) || { quelo_unlock_ttyln "  $(quelo_unlock_t invalid)"; sleep 1; return 1; }
  else
    idx=0
  fi

  part="${LUKS_PARTS[$idx]}"
  mapper="${LUKS_MAPPER_PREFIX}-${part##*/}"

  cryptsetup status "${mapper}" >/dev/null 2>&1 && \
    cryptsetup close "${mapper}" 2>/dev/null || true

  pass="$(quelo_unlock_luks_read_pass "$(quelo_unlock_t luks_pass_prompt)")" || {
    quelo_unlock_ttyln "  $(quelo_unlock_t cancel)"
    quelo_unlock_pause
    return 1
  }

  quelo_unlock_ttyln "  $(quelo_unlock_t running)"
  if ! printf '%s' "${pass}" | cryptsetup open --type luks "${part}" "${mapper}" 2>/dev/null; then
    quelo_unlock_ttyln "  $(quelo_unlock_t luks_bad_key)"
    quelo_unlock_pause
    return 1
  fi

  if mp="$(quelo_unlock_luks_mount_mapper "${mapper}")"; then
    quelo_unlock_ttyln "  $(quelo_unlock_t ok)"
    quelo_unlock_ttyln "  $(quelo_unlock_t luks_mounted) ${mp}"
    quelo_unlock_ttyln "  $(quelo_unlock_t luks_stays_open)"
  else
    quelo_unlock_ttyln "  $(quelo_unlock_t luks_open_no_mount)"
    quelo_unlock_ttyln "  /dev/mapper/${mapper}"
    rc=1
  fi

  quelo_unlock_ttyln ""
  quelo_unlock_ttyln "  $(quelo_unlock_t press_key)"
  quelo_unlock_pause
  return "${rc}"
}
