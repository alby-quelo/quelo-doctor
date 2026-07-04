#!/bin/bash
# Estensioni recuperabili (solo file d'uso utente).

quelo_rfiles_ext_whitelist() {
  printf '%s\n' \
    jpg jpeg png gif webp bmp tiff tif heic \
    mp4 mkv avi mov wmv mpeg mpg webm mts \
    mp3 flac wav ogg m4a aac wma \
    txt md rtf \
    pdf doc docx odt \
    xls xlsx ods csv \
    ppt pptx odp \
    db sqlite sqlite3 db3 mdb accdb mdf ldf ndf dbf fdb nsf odb sql dump backup fmp12 fp7 fmp realm \
    zip 7z rar \
    p7m p7s
}

quelo_rfiles_name_allowed() {
  local name="$1" base lower ext

  [[ -n "${name}" ]] || return 1
  base="${name##*/}"
  lower="${base,,}"

  case "${lower}" in
    *.h2.db|*.p7m|*.p7s) return 0 ;;
  esac

  [[ "${lower}" == *.* ]] || return 1
  ext="${lower##*.}"
  quelo_rfiles_ext_whitelist | grep -qx "${ext}"
}

quelo_rfiles_folder_label() {
  local filepath="$1" parent base

  parent="$(dirname "${filepath}")"
  base="$(basename "${parent}")"
  case "${base}" in
    ""|.|/|RECOVERED_FILES|RECOVERDIR|recuperati|recuperati_*|_vari) echo "_vari" ;;
    *) echo "${base}" ;;
  esac
}

quelo_rfiles_safe_folder() {
  local name="$1"

  name="${name//\//_}"
  name="${name// /_}"
  name="$(printf '%s' "${name}" | tr -cd '[:alnum:]._-')"
  [[ -n "${name}" ]] || name="_vari"
  echo "${name}"
}

quelo_rfiles_unique_path() {
  local dest="$1" n=1 try="${dest}"

  while [[ -e "${try}" ]]; do
    try="${dest%.*}_${n}.${dest##*.}"
    [[ "${dest}" == *.* ]] || try="${dest}_${n}"
    ((n++))
  done
  echo "${try}"
}
