#!/bin/bash
# Analisi persistenza: autostart, task, registry offline, estensioni browser.

quelo_scan_persist_bad_ext() {
  local f="$1" ext

  [[ -f "${f}" ]] || return 1
  ext=".${f##*.}"
  grep -qiFx "${ext}" /usr/local/share/quelo-scan/bad-ext.txt 2>/dev/null
}

quelo_scan_persist_check_file() {
  local f="$1" kind="$2"

  quelo_scan_persist_bad_ext "${f}" && \
    quelo_scan_register_hit "${f}" "persist-${kind}" "suspicious-path"
}

quelo_scan_persist_registry_runs() {
  local software="$1" logpfx="$2" out

  [[ -f "${software}" ]] || return 0

  if command -v hivexget >/dev/null 2>&1; then
    out="$(timeout 30 hivexget "${software}" 'Microsoft\Windows\CurrentVersion\Run' 2>/dev/null)" || out=""
    if [[ -n "${out}" ]]; then
      while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        quelo_scan_register_hit "${logpfx}/REGISTRY/Run/${line%%=*}" "persist" "Run=${line#*=}"
      done <<<"${out}"
      return 0
    fi
  fi

  command -v hivexml >/dev/null 2>&1 || return 0
  out="$(mktemp)"
  if timeout 60 hivexml "${software}" 2>/dev/null | grep -i 'Windows\\CurrentVersion\\Run' >"${out}"; then
    while IFS= read -r line; do
      [[ "${line}" == *"<value"* ]] || continue
      quelo_scan_register_hit "${logpfx}/REGISTRY/Run" "persist" "${line}"
    done <"${out}"
  fi
  rm -f "${out}"
}

quelo_scan_persist_scan_windows() {
  local root="$1" f

  while IFS= read -r f; do
    quelo_scan_persist_check_file "${f}" "windows"
  done < <(
    find "${root}/Users" \
      \( -path '*/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup/*' \
      -o -path '*/AppData/Local/Temp/*' \
      -o -path '*/Downloads/*' \) \
      -type f 2>/dev/null | head -4000
  )

  while IFS= read -r f; do
    quelo_scan_persist_check_file "${f}" "windows"
  done < <(
    find "${root}/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup" \
      "${root}/Windows/System32/Tasks" \
      "${root}/Windows/Tasks" \
      -type f 2>/dev/null | head -2000
  )

  [[ -f "${root}/Windows/System32/config/SOFTWARE" ]] && \
    quelo_scan_persist_registry_runs "${root}/Windows/System32/config/SOFTWARE" "${root}"
}

quelo_scan_persist_scan_browser() {
  local root="$1" f

  while IFS= read -r f; do
    quelo_scan_persist_check_file "${f}" "browser"
  done < <(
    find "${root}/Users" \
      \( -path '*/Google/Chrome/User Data/*/Extensions/*' \
      -o -path '*/Microsoft/Edge/User Data/*/Extensions/*' \
      -o -path '*/Mozilla/Firefox/Profiles/*/extensions/*' \
      -o -path '*/Opera Software/Opera Stable/Extensions/*' \) \
      -type f 2>/dev/null | head -3000
  )
}

quelo_scan_persist_scan_linux() {
  local root="$1" f

  while IFS= read -r f; do
    quelo_scan_persist_check_file "${f}" "linux"
  done < <(
    find "${root}/etc/cron.d" "${root}/etc/cron.daily" "${root}/etc/cron.hourly" \
      "${root}/etc/cron.weekly" "${root}/etc/cron.monthly" \
      "${root}/etc/systemd/system" "${root}/lib/systemd/system" \
      -type f 2>/dev/null | head -2000
  )

  while IFS= read -r f; do
    quelo_scan_persist_check_file "${f}" "linux"
  done < <(
    find "${root}/home" "${root}/root" \
      -path '*/.config/autostart/*' -type f 2>/dev/null | head -1000
  )
}

quelo_scan_persist_scan_roots() {
  local mode="${1:-all}" root fstype hit=0

  for root in "${SCAN_MOUNTS[@]}"; do
    [[ -d "${root}" ]] || continue
    fstype="$(findmnt -n -o FSTYPE --target "${root}" 2>/dev/null | head -1)"
    fstype="$(quelo_fs_normalize_type "${fstype}")"

    if [[ "${fstype}" == "ntfs" || -d "${root}/Windows" ]]; then
      SCAN_HAS_WINDOWS=1
      if [[ "${mode}" == "all" || "${mode}" == "persist" || "${mode}" == "windows" ]]; then
        quelo_scan_persist_scan_windows "${root}"
      fi
      if [[ "${mode}" == "all" || "${mode}" == "browser" ]]; then
        quelo_scan_persist_scan_browser "${root}"
      fi
      hit=1
    fi

    if [[ "${fstype}" =~ ^(ext2|ext3|ext4|btrfs|xfs)$ ]] || [[ -d "${root}/etc" ]]; then
      SCAN_HAS_LINUX=1
      if [[ "${mode}" == "all" || "${mode}" == "persist" || "${mode}" == "linux" ]]; then
        quelo_scan_persist_scan_linux "${root}"
      fi
      hit=1
    fi
  done

  ((hit))
}

quelo_scan_persist_run() {
  quelo_scan_log "=== Persistenza / autostart / estensioni ==="
  quelo_scan_progress 83 0 0 "persistenza"
  quelo_scan_persist_scan_roots "${1:-all}"
  quelo_scan_progress 85 1 1 "persistenza-ok"
}
