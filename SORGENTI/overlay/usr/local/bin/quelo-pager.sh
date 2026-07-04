#!/bin/bash
# Viewer stile man: txt → troff → man -l → less. Nel testo: q esci (come man).

quelo_pager_ui_is_en() {
  [[ -f /etc/default/locale ]] && grep -qE '^LANG=en_' /etc/default/locale
}

quelo_pager_troff_esc() {
  local t="$1"

  t="${t//\\/\\e}"
  if [[ "${t}" == .* ]]; then
    t="\\&${t}"
  fi
  if [[ "${t}" == -* ]]; then
    t="\\&${t}"
  fi
  printf '%s' "${t}"
}

quelo_pager_is_separator_line() {
  local line="$1" body="${line//[[:space:]]/}"

  [[ -z "${body}" ]] && return 0
  [[ "${body}" =~ ^[═─]+$ ]] && return 0
  return 1
}

quelo_pager_is_title_line() {
  local line="$1"

  [[ "${line}" == *"══"* ]] && return 0
  [[ "${line}" =~ ^(CREDITI|CREDITS|LICENZE|LICENSES|MANUALE|MANUAL|USER\ MANUAL) ]] && return 0
  [[ "${line}" =~ ^[0-9]+\ — ]] && return 0
  [[ "${line}" =~ ^(SISTEMA|OPERATING|SOFTWARE|THIRD|QUELO\ DOCTOR|Sezione|Section|CORRADO|Avvio|Boot|Navigazione|Navigation|Consigli|Tips|Versione|Version) ]] && return 0
  [[ "${line}" =~ ^Cos ]] && return 0
  [[ "${line}" =~ ^What ]] && return 0
  [[ "${line}" =~ ^[A-Z0-9][A-Z0-9\ /\(\)—\-]{4,}$ && "${line}" != *"http"* && "${line}" != *"→"* ]] && return 0
  return 1
}

quelo_pager_is_name_line() {
  local line="$1"

  [[ "${line}" =~ ^[[:space:]] ]] && return 1
  [[ "${line}" == *"→"* || "${line}" == *"http"* || "${line}" == *"══"* || "${line}" == *"──"* ]] && return 1
  quelo_pager_is_title_line "${line}" && return 1
  [[ "${line}" =~ ^[A-Z][A-Za-z0-9\ /+\(\)\.-]{2,}$ && "${#line}" -le 42 ]] && return 0
  return 1
}

quelo_pager_is_subsection_line() {
  local line="$1"

  [[ "${line}" =~ ^[[:space:]] ]] && return 1
  (( ${#line} > 32 )) && return 1
  [[ "${line}" == *"http"* || "${line}" == *"→"* ]] && return 1
  quelo_pager_is_title_line "${line}" && return 1
  quelo_pager_is_name_line "${line}" && return 1
  return 0
}

quelo_pager_txt_to_troff() {
  local src="$1" dst="$2" page="$3" title="$4"
  local line esc left right

  {
    printf '.TH %s 1 "Quelo Doctor" "Quelo Doctor"\n' "$(quelo_pager_troff_esc "${page^^}")"
    while IFS= read -r line || [[ -n "${line}" ]]; do
      if quelo_pager_is_separator_line "${line}"; then
        continue
      fi

      if [[ "${line}" =~ ^[[:space:]]+ ]]; then
        esc="$(quelo_pager_troff_esc "${line#"${line%%[![:space:]]*}"}")"
        printf '%s\n' "${esc}"
        continue
      fi

      if [[ "${line}" == *"→"* ]]; then
        left="${line%%→*}"
        right="${line#*→}"
        right="${right# }"
        printf '.TP\n.B %s\n' "$(quelo_pager_troff_esc "${left}")"
        printf '%s\n' "$(quelo_pager_troff_esc "${right}")"
        continue
      fi

      if [[ "${line}" =~ ^[[:space:]]*-[[:space:]] ]]; then
        esc="$(quelo_pager_troff_esc "${line#- }")"
        esc="${esc#"${esc%%[![:space:]]*}"}"
        printf '.IP \\(bu 3n\n%s\n' "${esc}"
        continue
      fi

      if quelo_pager_is_title_line "${line}" || quelo_pager_is_name_line "${line}" || quelo_pager_is_subsection_line "${line}"; then
        printf '.SH %s\n' "$(quelo_pager_troff_esc "${line}")"
        continue
      fi

      esc="$(quelo_pager_troff_esc "${line}")"
      printf '.PP\n%s\n' "${esc}"
    done <"${src}"
  } >"${dst}"
}

quelo_pager_show() {
  local file="$1" title="${2:-}" page="${3:-quelo-doc}"
  local troff cols

  [[ -f "${file}" && -r "${file}" ]] || return 1

  if ! command -v man >/dev/null 2>&1; then
    if quelo_pager_ui_is_en; then
      printf 'man-db not installed.\n' >/dev/tty 2>/dev/null
    else
      printf 'man-db non installato.\n' >/dev/tty 2>/dev/null
    fi
    sleep 2
    return 1
  fi

  cols=80
  stty size </dev/tty 2>/dev/null | read -r _ cols || true
  [[ -z "${cols}" || "${cols}" -lt 40 ]] && cols=80

  troff="$(mktemp -t quelo-man.XXXXXX)"
  quelo_pager_txt_to_troff "${file}" "${troff}" "${page}" "${title}"

  /usr/local/bin/quelo-clear-fb 2>/dev/null || true
  clear >/dev/tty 2>/dev/null || clear

  MANWIDTH="${cols}" MANROFFOPT="-c" \
    man -P "less -R" -l "${troff}" </dev/tty >/dev/tty 2>&1 || true

  rm -f "${troff}"
  return 0
}
