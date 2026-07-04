#!/bin/bash
# Reset password account Linux (chroot + passwd).

UNLOCK_CHROOT_MP="/mnt/quelo-unlock-linux"

quelo_unlock_linux_umount() {
  if mountpoint -q "${UNLOCK_CHROOT_MP}" 2>/dev/null; then
    umount -R "${UNLOCK_CHROOT_MP}" 2>/dev/null || umount -l "${UNLOCK_CHROOT_MP}" 2>/dev/null || true
  fi
}

quelo_unlock_linux_pick_root() {
  local disk="$1" part fstype mp flags

  LINUX_PARTS=()
  LINUX_MOUNTS=()
  LINUX_LABELS=()

  while IFS= read -r part; do
    [[ -n "${part}" ]] || continue
    quelo_live_is_medium_partition "${part}" && continue
    fstype="$(quelo_fs_normalize_type "$(quelo_fs_detect "${part}" 2>/dev/null)")"
    case "${fstype}" in
      ext2|ext3|ext4|btrfs|xfs) ;;
      *) continue ;;
    esac
    flags="$(lsblk -no PARTFLAGS "${part}" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    [[ "${flags}" == *"crypt"* ]] && continue
    mp="${UNLOCK_CHROOT_MP}"
    quelo_unlock_linux_umount
    mkdir -p "${mp}"
    if ! mount -o rw "${part}" "${mp}" 2>/dev/null; then
      continue
    fi
    [[ -f "${mp}/etc/passwd" ]] || { umount "${mp}" 2>/dev/null || true; continue; }
    LINUX_PARTS+=("${part}")
    LINUX_MOUNTS+=("${mp}")
    LINUX_LABELS+=("${part} ${fstype} $(lsblk -no SIZE "${part}" 2>/dev/null | head -1)")
    umount "${mp}" 2>/dev/null || true
  done < <(quelo_disk_enum_partitions "${disk}")

  ((${#LINUX_PARTS[@]} > 0))
}

quelo_unlock_linux_list_users() {
  local root="$1"

  awk -F: '($3 == 0 || ($3 >= 1000 && $3 < 65534)) && $1 != "nobody" { print $1 }' "${root}/etc/passwd" 2>/dev/null
}

quelo_unlock_linux_mount_chroot() {
  local part="$1" mp="${UNLOCK_CHROOT_MP}"

  quelo_unlock_linux_umount
  mkdir -p "${mp}"
  mount -o rw "${part}" "${mp}" || return 1

  if [[ -d "${mp}/boot/efi" ]]; then
    :
  fi
  for efi in "${mp}/boot/efi" "${mp}/efi"; do
    if [[ -d "${efi}" ]] && ! mountpoint -q "${efi}" 2>/dev/null; then
      :
    fi
  done

  mount --bind /dev "${mp}/dev" 2>/dev/null || true
  mount --bind /proc "${mp}/proc" 2>/dev/null || true
  mount --bind /sys "${mp}/sys" 2>/dev/null || true
  mount --bind /run "${mp}/run" 2>/dev/null || true
  return 0
}

quelo_unlock_linux_read_password() {
  local p1 p2

  quelo_unlock_ttyln "  $(quelo_unlock_t lin_pass_new)"
  if ! IFS= read -r -s p1 </dev/tty 2>/dev/null; then
    return 1
  fi
  quelo_unlock_tty $'\n'
  quelo_unlock_ttyln "  $(quelo_unlock_t lin_pass_confirm)"
  if ! IFS= read -r -s p2 </dev/tty 2>/dev/null; then
    return 1
  fi
  quelo_unlock_tty $'\n'
  [[ "${p1}" == "${p2}" ]] || return 1
  printf '%s' "${p1}"
}

quelo_unlock_linux_menu() {
  local disk="$1" i num idx choice user part newpass rc=0

  if ! quelo_unlock_linux_pick_root "${disk}"; then
    quelo_unlock_ttyln "  $(quelo_unlock_t lin_no_part)"
    quelo_unlock_ttyln "  $(quelo_unlock_t lin_luks_hint)"
    quelo_unlock_pause
    return 1
  fi

  if ((${#LINUX_PARTS[@]} > 1)); then
    quelo_unlock_ttyln ""
    quelo_unlock_ttyln "${C_AMBER}  $(quelo_unlock_t lin_pick_part)${C_RESET}"
    for i in "${!LINUX_PARTS[@]}"; do
      num=$((i + 1))
      quelo_unlock_ttyln "  ${C_GREEN}${num})${C_RESET} ${LINUX_LABELS[$i]}"
    done
    quelo_unlock_ttyln ""
    quelo_unlock_tty "${C_AMBER}  $(quelo_unlock_t prompt)${C_RESET}"
    quelo_unlock_read_choice || return 1
    choice="${DISK_CHOICE}"
    idx=$((choice - 1))
    ((idx >= 0 && idx < ${#LINUX_PARTS[@]})) || { quelo_unlock_ttyln "  $(quelo_unlock_t invalid)"; sleep 1; return 1; }
  else
    idx=0
  fi

  part="${LINUX_PARTS[$idx]}"
  if ! quelo_unlock_linux_mount_chroot "${part}"; then
    quelo_unlock_ttyln "  $(quelo_unlock_t fail)"
    quelo_unlock_linux_umount
    quelo_unlock_pause
    return 1
  fi

  quelo_unlock_ttyln ""
  quelo_unlock_ttyln "${C_AMBER}  $(quelo_unlock_t lin_pick_user)${C_RESET}"
  mapfile -t LINUX_USERS < <(quelo_unlock_linux_list_users "${UNLOCK_CHROOT_MP}")
  if ((${#LINUX_USERS[@]} == 0)); then
    quelo_unlock_ttyln "  $(quelo_unlock_t lin_no_users)"
    quelo_unlock_linux_umount
    quelo_unlock_pause
    return 1
  fi
  for i in "${!LINUX_USERS[@]}"; do
    num=$((i + 1))
    quelo_unlock_ttyln "  ${C_GREEN}${num})${C_RESET} ${LINUX_USERS[$i]}"
  done
  quelo_unlock_ttyln ""
  quelo_unlock_tty "${C_AMBER}  $(quelo_unlock_t prompt)${C_RESET}"
  quelo_unlock_read_choice || { quelo_unlock_linux_umount; return 1; }
  choice="${DISK_CHOICE}"
  idx=$((choice - 1))
  ((idx >= 0 && idx < ${#LINUX_USERS[@]})) || { quelo_unlock_ttyln "  $(quelo_unlock_t invalid)"; quelo_unlock_linux_umount; sleep 1; return 1; }
  user="${LINUX_USERS[$idx]}"

  newpass="$(quelo_unlock_linux_read_password)" || {
    quelo_unlock_ttyln "  $(quelo_unlock_t lin_pass_mismatch)"
    quelo_unlock_linux_umount
    quelo_unlock_pause
    return 1
  }

  if ! quelo_unlock_confirm_danger "${disk} Linux ${user}"; then
    quelo_unlock_ttyln "  $(quelo_unlock_t cancel)"
    quelo_unlock_linux_umount
    sleep 1
    return 0
  fi

  quelo_unlock_ttyln "  $(quelo_unlock_t running)"
  if printf '%s:%s\n' "${user}" "${newpass}" | chroot "${UNLOCK_CHROOT_MP}" chpasswd 2>/dev/null; then
    quelo_unlock_ttyln "  $(quelo_unlock_t ok)"
  else
    quelo_unlock_ttyln "  $(quelo_unlock_t fail)"
    rc=1
  fi

  sync
  quelo_unlock_linux_umount
  quelo_unlock_ttyln ""
  quelo_unlock_ttyln "  $(quelo_unlock_t reboot_hint)"
  quelo_unlock_ttyln "  $(quelo_unlock_t press_key)"
  quelo_unlock_pause
  return "${rc}"
}
