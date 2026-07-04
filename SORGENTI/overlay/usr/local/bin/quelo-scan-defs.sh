#!/bin/bash
# Aggiornamento definizioni antivirus (ClamAV) e info versione.

quelo_scan_defs_clam_dir() {
  echo "/var/lib/clamav"
}

quelo_scan_has_network() {
  local ip

  if command -v ip >/dev/null 2>&1; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ { for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }')"
    [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 0
  fi
  return 1
}

quelo_scan_defs_clam_info() {
  local dir main daily bc ver="?"

  dir="$(quelo_scan_defs_clam_dir)"
  main="${dir}/main.cvd"
  daily="${dir}/daily.cvd"
  bc="${dir}/bytecode.cvd"

  if [[ -f "${main}" ]]; then
    ver="$(awk '/^version:/ {print $2; exit}' "${main}" 2>/dev/null)" || ver="?"
    if [[ -f "${daily}" ]]; then
      ver="${ver}+$(awk '/^version:/ {print $2; exit}' "${daily}" 2>/dev/null)"
    fi
    echo "${ver}|$(stat -c '%y' "${main}" 2>/dev/null | cut -d. -f1)"
    return 0
  fi
  if [[ -f "${daily}" ]]; then
    ver="$(awk '/^version:/ {print $2; exit}' "${daily}" 2>/dev/null)"
    echo "${ver}|$(stat -c '%y' "${daily}" 2>/dev/null | cut -d. -f1)"
    return 0
  fi
  echo "?|?"
  return 1
}

quelo_scan_defs_yara_count() {
  local dir="${1:-/usr/local/share/quelo-scan/yara}"
  find "${dir}" -maxdepth 2 -name '*.yar' -o -name '*.yara' 2>/dev/null | wc -l
}

quelo_scan_defs_update() {
  local rc=0 timeout_sec=120 log

  log="$(mktemp)"
  if ! quelo_scan_has_network; then
    rm -f "${log}"
    return 2
  fi

  mkdir -p /var/lib/clamav /var/log/clamav /run/clamav 2>/dev/null || true
  chown -R clamav:clamav /var/lib/clamav /var/log/clamav /run/clamav 2>/dev/null || true

  if command -v freshclam >/dev/null 2>&1; then
    if timeout "${timeout_sec}" freshclam --stdout >"${log}" 2>&1; then
      :
    else
      rc=1
      grep -qiE 'already up-to-date|is up to date' "${log}" 2>/dev/null && rc=0
    fi
  else
    rc=1
  fi

  rm -f "${log}"
  return "${rc}"
}
