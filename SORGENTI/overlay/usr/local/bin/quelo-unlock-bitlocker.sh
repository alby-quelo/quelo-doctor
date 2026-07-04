#!/bin/bash
# Sblocco BitLocker con password o chiave di recupero (nessun brute-force).

BL_DISLOCK_MP="/mnt/quelo-bitlocker"
BL_CLEAR_MP="/mnt/quelo-bitlocker-clear"

quelo_unlock_bl_collect() {
  local disk="$1" part fstype

  BL_PARTS=()
  BL_LABELS=()

  while IFS= read -r part; do
    [[ -n "${part}" ]] || continue
    quelo_live_is_medium_partition "${part}" && continue
    fstype="$(blkid -o value -s TYPE "${part}" 2>/dev/null)" || fstype=""
    [[ "${fstype,,}" == "bitlocker" ]] || continue
    BL_PARTS+=("${part}")
    BL_LABELS+=("${part} $(lsblk -no SIZE "${part}" 2>/dev/null | head -1)")
  done < <(quelo_disk_enum_partitions "${disk}")

  ((${#BL_PARTS[@]} > 0))
}

quelo_unlock_bl_read_secret() {
  local prompt="$1" secret

  quelo_unlock_tty "${C_AMBER}  ${prompt}${C_RESET}"
  if ! IFS= read -r -s secret </dev/tty 2>/dev/null; then
    return 1
  fi
  quelo_unlock_tty $'\n'
  [[ -n "${secret}" ]] || return 1
  printf '%s' "${secret}"
}

quelo_unlock_bl_cleanup() {
  mountpoint -q "${BL_CLEAR_MP}" 2>/dev/null && umount "${BL_CLEAR_MP}" 2>/dev/null || true
  mountpoint -q "${BL_DISLOCK_MP}" 2>/dev/null && umount "${BL_DISLOCK_MP}" 2>/dev/null || true
}

quelo_unlock_bitlocker_menu() {
  local disk="$1" i num idx choice part method secret rc=0

  if ! command -v dislocker >/dev/null 2>&1; then
    quelo_unlock_ttyln "  $(quelo_unlock_t bl_no_tool)"
    quelo_unlock_pause
    return 1
  fi

  if ! quelo_unlock_bl_collect "${disk}"; then
    quelo_unlock_ttyln "  $(quelo_unlock_t bl_no_part)"
    quelo_unlock_pause
    return 1
  fi

  if ((${#BL_PARTS[@]} > 1)); then
    quelo_unlock_ttyln ""
    quelo_unlock_ttyln "${C_AMBER}  $(quelo_unlock_t bl_pick_part)${C_RESET}"
    for i in "${!BL_PARTS[@]}"; do
      num=$((i + 1))
      quelo_unlock_ttyln "  ${C_GREEN}${num})${C_RESET} ${BL_LABELS[$i]}"
    done
    quelo_unlock_ttyln ""
    quelo_unlock_tty "${C_AMBER}  $(quelo_unlock_t prompt)${C_RESET}"
    quelo_unlock_read_choice || return 1
    choice="${DISK_CHOICE}"
    idx=$((choice - 1))
    ((idx >= 0 && idx < ${#BL_PARTS[@]})) || { quelo_unlock_ttyln "  $(quelo_unlock_t invalid)"; sleep 1; return 1; }
  else
    idx=0
  fi

  part="${BL_PARTS[$idx]}"

  quelo_unlock_ttyln ""
  quelo_unlock_ttyln "${C_AMBER}  $(quelo_unlock_t bl_method)${C_RESET}"
  quelo_unlock_ttyln "  ${C_GREEN}1)${C_RESET} $(quelo_unlock_t bl_pass)"
  quelo_unlock_ttyln "  ${C_GREEN}2)${C_RESET} $(quelo_unlock_t bl_recovery)"
  quelo_unlock_ttyln ""
  quelo_unlock_tty "${C_AMBER}  $(quelo_unlock_t prompt)${C_RESET}"
  quelo_unlock_read_choice || return 1
  choice="${DISK_CHOICE}"

  case "${choice}" in
    1)
      method="pass"
      secret="$(quelo_unlock_bl_read_secret "$(quelo_unlock_t bl_pass_prompt)")" || {
        quelo_unlock_ttyln "  $(quelo_unlock_t cancel)"
        quelo_unlock_pause
        return 1
      }
      ;;
    2)
      method="recovery"
      secret="$(quelo_unlock_bl_read_secret "$(quelo_unlock_t bl_recovery_prompt)")" || {
        quelo_unlock_ttyln "  $(quelo_unlock_t cancel)"
        quelo_unlock_pause
        return 1
      }
      secret="${secret//-/}"
      ;;
    *)
      quelo_unlock_ttyln "  $(quelo_unlock_t invalid)"
      sleep 1
      return 1
      ;;
  esac

  quelo_unlock_bl_cleanup
  mkdir -p "${BL_DISLOCK_MP}" "${BL_CLEAR_MP}"

  quelo_unlock_ttyln "  $(quelo_unlock_t running)"
  if [[ "${method}" == "pass" ]]; then
    dislocker -V "${part}" -p"${secret}" -- "${BL_DISLOCK_MP}" >/dev/null 2>&1 || rc=1
  else
    dislocker -V "${part}" -r"${secret}" -- "${BL_DISLOCK_MP}" >/dev/null 2>&1 || rc=1
  fi

  if ((rc != 0)) || [[ ! -f "${BL_DISLOCK_MP}/dislocker-file" ]]; then
    quelo_unlock_ttyln "  $(quelo_unlock_t bl_bad_key)"
    quelo_unlock_bl_cleanup
    quelo_unlock_pause
    return 1
  fi

  if mount -o loop,rw "${BL_DISLOCK_MP}/dislocker-file" "${BL_CLEAR_MP}" 2>/dev/null; then
    quelo_unlock_ttyln "  $(quelo_unlock_t ok)"
    quelo_unlock_ttyln "  $(quelo_unlock_t bl_mounted) ${BL_CLEAR_MP}"
    quelo_unlock_ttyln "  $(quelo_unlock_t bl_stays_open)"
  else
    quelo_unlock_ttyln "  $(quelo_unlock_t fail)"
    rc=1
  fi

  quelo_unlock_ttyln ""
  quelo_unlock_ttyln "  $(quelo_unlock_t press_key)"
  quelo_unlock_pause
  return "${rc}"
}
