#!/bin/bash
# Motori scansione: ClamAV, YARA, chkrootkit, progresso, quarantena.

SCAN_STAT_INFECTED=0
SCAN_STAT_QUARANTINE=0
SCAN_STAT_DELETED=0
SCAN_STAT_REPAIRED=0
SCAN_STAT_FAILED=0
SCAN_MODE="report"
SCAN_QUAR_ROOT=""
SCAN_LOG_FILE=""
SCAN_START_TS=0
SCAN_HAS_WINDOWS=0
SCAN_HAS_LINUX=0
SCAN_MOUNTS=()
SCAN_DISK=""
SCAN_FILE_TOTAL=0
SCAN_FILE_DONE=0
SCAN_ENGINE_LOADED=0
SCAN_YARA_TIMEOUT=180
SCAN_ROOTKIT_TIMEOUT=300

quelo_scan_find_prune_expr() {
  printf '%s' '\( -path '"'"'*/WinSxS/*'"'"' -o -path '"'"'*/$Recycle.Bin/*'"'"' -o -path '"'"'*/System Volume Information/*'"'"' -o -name pagefile.sys -o -name hiberfil.sys -o -name swapfile.sys \) -prune -o'
}

quelo_scan_log() {
  local ts line

  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  line="[${ts}] $*"
  SCAN_LOG_LINES+=("${line}")
  [[ -n "${SCAN_LOG_FILE}" ]] && printf '%s\n' "${line}" >>"${SCAN_LOG_FILE}"
}

quelo_scan_progress() {
  local pct="$1" done="$2" total="$3" msg="$4"
  local width=20 filled empty bar

  ((pct < 0)) && pct=0
  ((pct > 100)) && pct=100
  filled=$((pct * width / 100))
  empty=$((width - filled))
  bar="$(printf '%*s' "${filled}" '' | tr ' ' '#')$(printf '%*s' "${empty}" '' | tr ' ' '.')"
  printf '\r  %b[%s]%b %3d%%' "${C_GREEN:-}" "${bar}" "${C_RESET:-}" "${pct}" >/dev/tty 2>/dev/null || \
    printf '\r  [%s] %3d%%' "${bar}" "${pct}"
  if ((total > 0)); then
    printf ' (%d/%d) %s' "${done}" "${total}" "${msg}" >/dev/tty 2>/dev/null || \
      printf ' (%d/%d) %s' "${done}" "${total}" "${msg}"
  else
    printf ' %s' "${msg}" >/dev/tty 2>/dev/null || printf ' %s' "${msg}"
  fi
  printf '\033[K' >/dev/tty 2>/dev/null || true
}

quelo_scan_progress_end() {
  printf '\n' >/dev/tty 2>/dev/null || echo ""
}

quelo_scan_duration_fmt() {
  local secs="$1" h m s

  ((secs < 0)) && secs=0
  h=$((secs / 3600))
  m=$(((secs % 3600) / 60))
  s=$((secs % 60))
  printf '%02d:%02d:%02d' "${h}" "${m}" "${s}"
}

quelo_scan_register_hit() {
  local path="$1" engine="$2" sig="$3"

  ((SCAN_STAT_INFECTED++))
  quelo_scan_log "HIT ${engine} ${sig} :: ${path}"
  quelo_scan_handle_threat "${path}" "${engine}" "${sig}"
}

quelo_scan_ask_action() {
  local path="$1" engine="$2" sig="$3" prompt reply

  if quelo_scan_ui_is_en; then
    prompt="  Threat: ${path}\n  ${engine}: ${sig}\n  [q]uarantine [d]elete [s]kip: "
  else
    prompt="  Minaccia: ${path}\n  ${engine}: ${sig}\n  [q]uarantena [c]ancella [s]alta: "
  fi
  printf '%b' "${prompt}" >/dev/tty 2>/dev/null || printf '%s' "${prompt}"
  if ! IFS= read -r -n 1 -s reply </dev/tty 2>/dev/null; then
  printf '\n' >/dev/tty 2>/dev/null || true
    return 1
  fi
  printf '\n' >/dev/tty 2>/dev/null || true
  case "${reply}" in
    q|Q|c|C|d|D) echo "${reply}" ;;
    *) echo "s" ;;
  esac
}

quelo_scan_quarantine_file() {
  local src="$1" rel dest meta

  [[ -f "${src}" ]] || { ((SCAN_STAT_FAILED++)); return 1; }
  [[ -n "${SCAN_QUAR_ROOT}" ]] || { ((SCAN_STAT_FAILED++)); return 1; }

  rel="${src#/}"
  dest="${SCAN_QUAR_ROOT}/files/${rel}"
  mkdir -p "$(dirname "${dest}")" "${SCAN_QUAR_ROOT}/meta" 2>/dev/null || true

  if cp -a -- "${src}" "${dest}" 2>/dev/null && rm -f -- "${src}" 2>/dev/null; then
    meta="${SCAN_QUAR_ROOT}/meta/manifest.txt"
    printf '%s|%s|%s\n' "$(date -Iseconds)" "${src}" "${dest}" >>"${meta}"
    ((SCAN_STAT_QUARANTINE++))
    quelo_scan_log "QUARANTINE ${src} -> ${dest}"
    return 0
  fi
  ((SCAN_STAT_FAILED++))
  quelo_scan_log "QUARANTINE-FAIL ${src}"
  return 1
}

quelo_scan_delete_file() {
  local src="$1"

  if rm -f -- "${src}" 2>/dev/null; then
    ((SCAN_STAT_DELETED++))
    quelo_scan_log "DELETE ${src}"
    return 0
  fi
  ((SCAN_STAT_FAILED++))
  quelo_scan_log "DELETE-FAIL ${src}"
  return 1
}

quelo_scan_handle_threat() {
  local path="$1" engine="$2" sig="$3" act

  [[ -e "${path}" ]] || return 0

  case "${SCAN_MODE}" in
    report)
      quelo_scan_log "REPORT-ONLY ${path}"
      return 0
      ;;
    auto)
      quelo_scan_quarantine_file "${path}" || true
      return 0
      ;;
    ask)
      act="$(quelo_scan_ask_action "${path}" "${engine}" "${sig}")" || act="s"
      case "${act}" in
        q|Q) quelo_scan_quarantine_file "${path}" || true ;;
        c|C|d|D) quelo_scan_delete_file "${path}" || true ;;
        *) quelo_scan_log "SKIP ${path}" ;;
      esac
      ;;
  esac
}

quelo_scan_count_files() {
  local root total=0 prune

  SCAN_FILE_TOTAL=0
  prune="$(quelo_scan_find_prune_expr)"
  quelo_scan_progress 3 0 0 "conteggio-file"
  for root in "${SCAN_MOUNTS[@]}"; do
    [[ -d "${root}" ]] || continue
    # shellcheck disable=SC2086
    total=$((total + $(find "${root}" -xdev ${prune} -type f -print 2>/dev/null | wc -l)))
  done
  SCAN_FILE_TOTAL="${total}"
}

quelo_scan_mount_disk() {
  local disk="$1" part fstype mp ro

  SCAN_MOUNTS=()
  SCAN_HAS_WINDOWS=0
  SCAN_HAS_LINUX=0
  quelo_block_disk_probe "${disk}"

  ro="ro"
  [[ "${SCAN_MODE}" == "report" ]] && ro="ro"

  while IFS= read -r part; do
    [[ -n "${part}" ]] || continue
    quelo_live_is_medium_partition "${part}" && continue
    fstype="$(quelo_fs_detect "${part}" 2>/dev/null)" || fstype=""
    quelo_fs_should_skip_mount "${fstype}" && continue
    [[ -z "${fstype}" ]] && continue

    mp="$(findmnt -n -o TARGET --source "${part}" 2>/dev/null)" || mp=""
    if [[ -z "${mp}" ]]; then
      mp="/mnt/quelo-scan/${part##*/}"
      mkdir -p "${mp}"
      case "${fstype}" in
        ntfs)
          mount -t ntfs-3g -o "${ro}" "${part}" "${mp}" 2>/dev/null \
            || mount -o "${ro}" "${part}" "${mp}" 2>/dev/null || continue
          ;;
        vfat|exfat)
          mount -o "${ro}" "${part}" "${mp}" 2>/dev/null || continue
          ;;
        *)
          mount -o "${ro}" "${part}" "${mp}" 2>/dev/null || continue
          ;;
      esac
    fi
    [[ -d "${mp}" ]] || continue
    SCAN_MOUNTS+=("${mp}")
    [[ -d "${mp}/Windows" ]] && SCAN_HAS_WINDOWS=1
    [[ -d "${mp}/etc" ]] && SCAN_HAS_LINUX=1
  done < <(quelo_disk_enum_partitions "${disk}")
}

quelo_scan_remount_rw_if_needed() {
  local mp

  [[ "${SCAN_MODE}" == "report" ]] && return 0
  for mp in "${SCAN_MOUNTS[@]}"; do
    mount -o remount,rw "${mp}" 2>/dev/null || true
  done
}

quelo_scan_unmount_all() {
  local mp

  for mp in "${SCAN_MOUNTS[@]}"; do
    mountpoint -q "${mp}" 2>/dev/null || continue
    umount "${mp}" 2>/dev/null || umount -l "${mp}" 2>/dev/null || true
  done
  SCAN_MOUNTS=()
}

quelo_scan_run_clamav() {
  local root done=0 total="${SCAN_FILE_TOTAL}" pct line path sig

  command -v clamscan >/dev/null 2>&1 || {
    quelo_scan_log "ClamAV non disponibile"
    return 1
  }

  quelo_scan_log "ClamAV scan start (files ~${total})"
  quelo_scan_progress 12 0 "${total}" "clamav"

  for root in "${SCAN_MOUNTS[@]}"; do
    [[ -d "${root}" ]] || continue
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      if [[ "${line}" == *" FOUND" ]]; then
        path="${line%%: *}"
        path="${path##* -> }"
        sig="${line#*: }"
        sig="${sig% FOUND}"
        quelo_scan_register_hit "${path}" "ClamAV" "${sig}"
      elif [[ "${line}" == *": OK" ]]; then
        ((done++))
        path="${line%%: OK}"
        if ((total > 0)); then
          pct=$((12 + done * 68 / total))
          ((pct > 80)) && pct=80
        else
          pct=$((12 + done * 68 / 10000))
          ((pct > 80)) && pct=80
        fi
        quelo_scan_progress "${pct}" "${done}" "${total}" "$(basename "${path}")"
      fi
    done < <(
      if command -v stdbuf >/dev/null 2>&1; then
        stdbuf -oL -eL clamscan -r --stdout --verbose "${root}" 2>&1
      else
        clamscan -r --stdout --verbose "${root}" 2>&1
      fi
    )
    quelo_scan_log "ClamAV root ${root} scanned=${done}"
  done

  quelo_scan_progress 82 "${done}" "${total}" "clamav-ok"
}

quelo_scan_build_yara_targets() {
  local list="$1" root prune extargs

  : >"${list}"
  prune="$(quelo_scan_find_prune_expr)"
  extargs=()
  while IFS= read -r ext; do
    [[ -n "${ext}" ]] || continue
    extargs+=(-iname "*${ext}")
    extargs+=(-o)
  done </usr/local/share/quelo-scan/bad-ext.txt
  unset 'extargs[${#extargs[@]}-1]'

  for root in "${SCAN_MOUNTS[@]}"; do
    [[ -d "${root}" ]] || continue
    # shellcheck disable=SC2086
    find "${root}" -xdev ${prune} -type f -size -64M \( "${extargs[@]}" \) -print 2>/dev/null \
      | head -12000 >>"${list}"
  done
}

quelo_scan_run_yara() {
  local rules rule pct done=0 total yara_out list fcount

  command -v yara >/dev/null 2>&1 || {
    quelo_scan_log "YARA non disponibile"
    return 1
  }

  rules=()
  while IFS= read -r -d '' rule; do
    rules+=("${rule}")
  done < <(find /usr/local/share/quelo-scan/yara -type f \( -name '*.yar' -o -name '*.yara' \) -print0 2>/dev/null)

  ((${#rules[@]} == 0)) && {
    quelo_scan_log "Nessuna regola YARA"
    quelo_scan_progress 92 0 0 "yara-skip"
    return 0
  }

  list="$(mktemp)"
  quelo_scan_progress 86 0 0 "yara-prepare"
  quelo_scan_build_yara_targets "${list}"
  fcount="$(wc -l <"${list}" | tr -d '[:space:]')"
  quelo_scan_log "YARA scan (${#rules[@]} rules, ${fcount} targets)"

  if [[ "${fcount}" == "0" ]]; then
    rm -f "${list}"
    quelo_scan_progress 92 0 0 "yara-skip"
    return 0
  fi

  total="${#rules[@]}"
  for rule in "${rules[@]}"; do
    pct=$((86 + done * 6 / (total > 0 ? total : 1)))
    quelo_scan_progress "${pct}" "${done}" "${total}" "$(basename "${rule}")"
    yara_out="$(mktemp)"
    if timeout "${SCAN_YARA_TIMEOUT}" xargs -r -a "${list}" -n 80 yara -w "${rule}" >"${yara_out}" 2>/dev/null; then
      while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        quelo_scan_register_hit "${line#* }" "YARA" "${line%% *}"
      done <"${yara_out}"
    else
      quelo_scan_log "YARA timeout/skip $(basename "${rule}")"
    fi
    rm -f "${yara_out}"
    ((done++))
  done
  rm -f "${list}"
  quelo_scan_progress 92 "${done}" "${total}" "yara-ok"
}

quelo_scan_run_rootkit() {
  local root line

  ((SCAN_HAS_LINUX)) || {
    quelo_scan_log "Nessuna partizione Linux per rootkit scan"
    quelo_scan_progress 96 1 1 "rootkit-skip"
    return 0
  }

  quelo_scan_log "Rootkit scan (chkrootkit)"
  quelo_scan_progress 94 0 0 "rootkit"

  for root in "${SCAN_MOUNTS[@]}"; do
    [[ -d "${root}/etc" ]] || continue

    if command -v chkrootkit >/dev/null 2>&1; then
      while IFS= read -r line; do
        [[ "${line}" == *"INFECTED"* ]] || continue
        quelo_scan_register_hit "${root}" "chkrootkit" "${line}"
      done < <(timeout "${SCAN_ROOTKIT_TIMEOUT}" chkrootkit -r "${root}" 2>/dev/null)
    fi
  done

  quelo_scan_progress 96 1 1 "rootkit-ok"
}

quelo_scan_run_full() {
  quelo_scan_run_clamav
  # shellcheck disable=SC1091
  . "${Q_BIN}/quelo-scan-persist.sh"
  quelo_scan_persist_run
  quelo_scan_run_yara
  quelo_scan_run_rootkit
}

quelo_scan_show_summary() {
  local elapsed

  elapsed=$(($(date +%s) - SCAN_START_TS))
  quelo_scan_ttyln ""
  quelo_scan_ttyln "=================================="
  quelo_scan_ttyln "  $(quelo_scan_t summary_title)"
  quelo_scan_ttyln "=================================="
  quelo_scan_ttyln "  $(quelo_scan_t stat_infected):      ${SCAN_STAT_INFECTED}"
  quelo_scan_ttyln "  $(quelo_scan_t stat_quarantine):    ${SCAN_STAT_QUARANTINE}"
  quelo_scan_ttyln "  $(quelo_scan_t stat_deleted):       ${SCAN_STAT_DELETED}"
  quelo_scan_ttyln "  $(quelo_scan_t stat_repaired):      ${SCAN_STAT_REPAIRED}"
  quelo_scan_ttyln "  $(quelo_scan_t stat_failed):        ${SCAN_STAT_FAILED}"
  quelo_scan_ttyln "  $(quelo_scan_t stat_duration):      $(quelo_scan_duration_fmt "${elapsed}")"
  quelo_scan_ttyln "=================================="
  quelo_scan_log "SUMMARY infected=${SCAN_STAT_INFECTED} quarantine=${SCAN_STAT_QUARANTINE} deleted=${SCAN_STAT_DELETED} failed=${SCAN_STAT_FAILED} duration=${elapsed}s"
}

quelo_scan_save_log_prompt() {
  local dest dir base ts reply

  quelo_scan_ttyln ""
  quelo_scan_tty "$(quelo_scan_t save_log_prompt)"
  if ! quelo_scan_confirm_yn; then
    return 0
  fi

  dest="$(quelo_scan_pick_log_dest)" || return 0
  ts="$(date +%Y%m%d-%H%M%S)"
  base="quelo-scan-${SCAN_DISK##*/}-${ts}.txt"
  dir="${dest%/}/${base}"
  cp "${SCAN_LOG_FILE}" "${dir}" 2>/dev/null && \
    quelo_fs_publish_export "${dir}" && \
    quelo_scan_ttyln "  $(printf "$(quelo_scan_t save_log_ok)" "${dir}")" || \
    quelo_scan_ttyln "  $(quelo_scan_t save_log_fail)"
}
