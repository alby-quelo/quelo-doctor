#!/bin/bash
# Motori di recupero file (ext / ntfs) con barra di avanzamento.

_QE_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck disable=SC1091
. "${_QE_DIR}/quelo-recover-files-whitelist.sh"

RFILES_STAT_FILES=0
RFILES_STAT_FOLDERS=0
RFILES_STAT_BYTES=0

quelo_rfiles_progress() {
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
  printf '\n' >/dev/tty 2>/dev/null || echo ""
}

quelo_rfiles_import_tree() {
  local src_root="$1" dest_root="$2"
  local f folder safe dest_dir dest_file base size

  RFILES_STAT_FILES=0
  RFILES_STAT_BYTES=0
  RFILES_STAT_FOLDERS=0
  declare -A RFILES_SEEN_FOLDERS=()

  [[ -d "${src_root}" ]] || return 0

  local file_list=()
  while IFS= read -r -d '' f; do
    file_list+=("${f}")
  done < <(find "${src_root}" -type f -print0 2>/dev/null)

  local total="${#file_list[@]}" done=0 pct_div=1
  ((total > 0)) && pct_div="${total}"
  for f in "${file_list[@]}"; do
    ((done++))
    base="$(basename "${f}")"
    quelo_rfiles_progress $((30 + 65 * done / pct_div)) "${done}" "${total}" "${base}"
    quelo_rfiles_name_allowed "${base}" || continue

    folder="$(quelo_rfiles_folder_label "${f}")"
    safe="$(quelo_rfiles_safe_folder "${folder}")"
    dest_dir="${dest_root}/${safe}"
    mkdir -p "${dest_dir}"
    RFILES_SEEN_FOLDERS["${safe}"]=1

    dest_file="$(quelo_rfiles_unique_path "${dest_dir}/${base}")"
    cp -a "${f}" "${dest_file}" 2>/dev/null || cp "${f}" "${dest_file}" 2>/dev/null || continue
    size="$(stat -c '%s' "${dest_file}" 2>/dev/null || echo 0)"
    RFILES_STAT_BYTES=$((RFILES_STAT_BYTES + size))
    ((RFILES_STAT_FILES++))
  done

  RFILES_STAT_FOLDERS=${#RFILES_SEEN_FOLDERS[@]}
  quelo_rfiles_progress 100 "${done}" "${total}" "done"
}

quelo_rfiles_recover_ext() {
  local part="$1" dest="$2"
  local staging work root rc=0

  staging="$(mktemp -d /run/quelo-rfiles.XXXXXX)"
  work="${staging}/work"
  mkdir -p "${work}"

  quelo_rfiles_progress 8 0 0 "prepare"

  if command -v extundelete >/dev/null 2>&1; then
    (cd "${work}" && extundelete "${part}" --restore-all) || rc=1
    root="${work}/RECOVERED_FILES"
  else
    rc=1
  fi

  if [[ ! -d "${root}" ]] && command -v ext4magic >/dev/null 2>&1; then
    mkdir -p "${work}/magic"
    ext4magic "${part}" -d "${work}/magic" -a 1 -b "$(date +%s)" -r 2>/dev/null || true
    if [[ -d "${work}/magic/RECOVERDIR" ]]; then
      root="${work}/magic/RECOVERDIR"
      rc=0
    fi
  fi

  if [[ ! -d "${root}" ]]; then
    rm -rf "${staging}"
    return 1
  fi

  quelo_rfiles_progress 25 0 0 "scan"
  quelo_rfiles_import_tree "${root}" "${dest}"
  rm -rf "${staging}"
  return "${rc}"
}

quelo_rfiles_recover_ntfs() {
  local part="$1" dest="$2"
  local line pct done total msg

  RFILES_STAT_FILES=0
  RFILES_STAT_FOLDERS=0
  RFILES_STAT_BYTES=0

  if ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi

  while IFS= read -r line; do
    case "${line}" in
      PROGRESS:*)
        IFS=: read -r _ pct done total msg <<<"${line}"
        quelo_rfiles_progress "${pct}" "${done}" "${total}" "${msg}"
        ;;
      SUMMARY:*)
        IFS=: read -r _ RFILES_STAT_FILES RFILES_STAT_FOLDERS RFILES_STAT_BYTES <<<"${line}"
        ;;
      ERROR:*)
        return 1
        ;;
    esac
  done < <(python3 "${_QE_DIR}/quelo-ntfs-recover.py" "${part}" "${dest}" 2>/dev/null)

  return 0
}

quelo_rfiles_human_bytes() {
  local bytes="$1"

  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B "${bytes}" 2>/dev/null || echo "${bytes}B"
  elif ((bytes >= 1073741824)); then
    printf '%.1f GB' "$(awk "BEGIN {print ${bytes}/1073741824}")"
  elif ((bytes >= 1048576)); then
    printf '%.1f MB' "$(awk "BEGIN {print ${bytes}/1048576}")"
  else
    echo "${bytes}B"
  fi
}

quelo_rfiles_format_duration() {
  local secs="$1" h m

  h=$((secs / 3600))
  m=$(((secs % 3600) / 60))
  printf '%02d:%02d' "${h}" "${m}"
}
