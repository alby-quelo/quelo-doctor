#!/bin/bash
# Reset password account Windows (SAM offline, chntpw).

quelo_unlock_win_list_users() {
  local sam="$1"

  chntpw -l "${sam}" 2>/dev/null | awk -F'|' '
    /^\|/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
      if ($3 != "" && $3 !~ /^Username/) print $3
    }'
}

quelo_unlock_win_run_chntpw() {
  local sam="$1" user="$2" choice="$3" newpass="${4:-}"

  case "${choice}" in
    clear)
      printf '1\ny\n' | chntpw -u "${user}" "${sam}" >/dev/null 2>&1
      ;;
    newpass)
      printf '2\n%s\n%s\ny\n' "${newpass}" "${newpass}" | chntpw -u "${user}" "${sam}" >/dev/null 2>&1
      ;;
    admin)
      printf '3\ny\n' | chntpw -u "${user}" "${sam}" >/dev/null 2>&1
      ;;
    unlock)
      printf '4\ny\n' | chntpw -u "${user}" "${sam}" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

quelo_unlock_win_pick_partition() {
  local disk="$1" part fstype mp

  WIN_PARTS=()
  WIN_MOUNTS=()
  WIN_LABELS=()

  while IFS= read -r part; do
    [[ -n "${part}" ]] || continue
    quelo_live_is_medium_partition "${part}" && continue
    fstype="$(quelo_fs_normalize_type "$(quelo_fs_detect "${part}" 2>/dev/null)")"
    [[ "${fstype}" == "ntfs" ]] || continue
    mp="/mnt/quelo-unlock/win-${part##*/}"
    mkdir -p "${mp}"
    if ! mount -t ntfs-3g -o rw "${part}" "${mp}" 2>/dev/null; then
      mount -o rw "${part}" "${mp}" 2>/dev/null || continue
    fi
    [[ -f "${mp}/Windows/System32/config/SAM" ]] || { umount "${mp}" 2>/dev/null || true; continue; }
    WIN_PARTS+=("${part}")
    WIN_MOUNTS+=("${mp}")
    WIN_LABELS+=("${part} $(lsblk -no SIZE "${part}" 2>/dev/null | head -1)")
  done < <(quelo_disk_enum_partitions "${disk}")

  ((${#WIN_PARTS[@]} > 0))
}

quelo_unlock_win_umount_all() {
  local mp
  for mp in "${WIN_MOUNTS[@]:-}"; do
    mountpoint -q "${mp}" 2>/dev/null && umount "${mp}" 2>/dev/null || true
  done
}

quelo_unlock_win_read_password() {
  local p1 p2

  quelo_unlock_ttyln "  $(quelo_unlock_t win_pass_new)"
  if ! IFS= read -r -s p1 </dev/tty 2>/dev/null; then
    return 1
  fi
  quelo_unlock_tty $'\n'
  quelo_unlock_ttyln "  $(quelo_unlock_t win_pass_confirm)"
  if ! IFS= read -r -s p2 </dev/tty 2>/dev/null; then
    return 1
  fi
  quelo_unlock_tty $'\n'
  [[ "${p1}" == "${p2}" ]] || return 1
  printf '%s' "${p1}"
}

quelo_unlock_windows_menu() {
  local disk="$1" i num idx choice user sam config action newpass rc=0

  if ! quelo_unlock_win_pick_partition "${disk}"; then
    quelo_unlock_ttyln "  $(quelo_unlock_t win_no_part)"
    quelo_unlock_pause
    return 1
  fi

  if ((${#WIN_PARTS[@]} > 1)); then
    quelo_unlock_ttyln ""
    quelo_unlock_ttyln "${C_AMBER}  $(quelo_unlock_t win_pick_part)${C_RESET}"
    for i in "${!WIN_PARTS[@]}"; do
      num=$((i + 1))
      quelo_unlock_ttyln "  ${C_GREEN}${num})${C_RESET} ${WIN_LABELS[$i]}"
    done
    quelo_unlock_ttyln ""
    quelo_unlock_tty "${C_AMBER}  $(quelo_unlock_t prompt)${C_RESET}"
    quelo_unlock_read_choice || { quelo_unlock_win_umount_all; return 1; }
    choice="${DISK_CHOICE}"
    idx=$((choice - 1))
    ((idx >= 0 && idx < ${#WIN_PARTS[@]})) || { quelo_unlock_ttyln "  $(quelo_unlock_t invalid)"; quelo_unlock_win_umount_all; sleep 1; return 1; }
  else
    idx=0
  fi

  config="${WIN_MOUNTS[$idx]}/Windows/System32/config"
  sam="${config}/SAM"

  quelo_unlock_ttyln ""
  quelo_unlock_ttyln "${C_AMBER}  $(quelo_unlock_t win_pick_user)${C_RESET}"
  mapfile -t WIN_USERS < <(quelo_unlock_win_list_users "${sam}")
  if ((${#WIN_USERS[@]} == 0)); then
    quelo_unlock_ttyln "  $(quelo_unlock_t win_no_users)"
    quelo_unlock_win_umount_all
    quelo_unlock_pause
    return 1
  fi
  for i in "${!WIN_USERS[@]}"; do
    num=$((i + 1))
    quelo_unlock_ttyln "  ${C_GREEN}${num})${C_RESET} ${WIN_USERS[$i]}"
  done
  quelo_unlock_ttyln ""
  quelo_unlock_tty "${C_AMBER}  $(quelo_unlock_t prompt)${C_RESET}"
  quelo_unlock_read_choice || { quelo_unlock_win_umount_all; return 1; }
  choice="${DISK_CHOICE}"
  idx=$((choice - 1))
  ((idx >= 0 && idx < ${#WIN_USERS[@]})) || { quelo_unlock_ttyln "  $(quelo_unlock_t invalid)"; quelo_unlock_win_umount_all; sleep 1; return 1; }
  user="${WIN_USERS[$idx]}"

  while true; do
    quelo_unlock_ttyln ""
    quelo_unlock_ttyln "${C_AMBER}  $(quelo_unlock_t win_action) — ${user}${C_RESET}"
    quelo_unlock_ttyln "  ${C_GREEN}1)${C_RESET} $(quelo_unlock_t win_act_new)"
    quelo_unlock_ttyln "  ${C_GREEN}2)${C_RESET} $(quelo_unlock_t win_act_clear)"
    quelo_unlock_ttyln "  ${C_GREEN}3)${C_RESET} $(quelo_unlock_t win_act_unlock)"
    quelo_unlock_ttyln "  ${C_GREEN}4)${C_RESET} $(quelo_unlock_t win_act_admin)"
    quelo_unlock_ttyln ""
    quelo_unlock_tty "${C_AMBER}  $(quelo_unlock_t prompt)${C_RESET}"
    quelo_unlock_read_choice || { quelo_unlock_win_umount_all; return 1; }
    choice="${DISK_CHOICE}"
    case "${choice}" in
      1) action="newpass" ;;
      2) action="clear" ;;
      3) action="unlock" ;;
      4) action="admin" ;;
      *) quelo_unlock_ttyln "  $(quelo_unlock_t invalid)"; sleep 1; continue ;;
    esac
    break
  done

  if ! quelo_unlock_confirm_danger "${disk} Windows ${user}"; then
    quelo_unlock_ttyln "  $(quelo_unlock_t cancel)"
    quelo_unlock_win_umount_all
    sleep 1
    return 0
  fi

  newpass=""
  if [[ "${action}" == "newpass" ]]; then
    newpass="$(quelo_unlock_win_read_password)" || {
      quelo_unlock_ttyln "  $(quelo_unlock_t win_pass_mismatch)"
      quelo_unlock_win_umount_all
      quelo_unlock_pause
      return 1
    }
  fi

  quelo_unlock_ttyln "  $(quelo_unlock_t running)"
  if quelo_unlock_win_run_chntpw "${sam}" "${user}" "${action}" "${newpass}"; then
    quelo_unlock_ttyln "  $(quelo_unlock_t ok)"
  else
    quelo_unlock_ttyln "  $(quelo_unlock_t fail)"
    rc=1
  fi

  sync
  quelo_unlock_win_umount_all
  quelo_unlock_ttyln ""
  quelo_unlock_ttyln "  $(quelo_unlock_t reboot_hint)"
  quelo_unlock_ttyln "  $(quelo_unlock_t press_key)"
  quelo_unlock_pause
  return "${rc}"
}
