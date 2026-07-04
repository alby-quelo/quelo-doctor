#!/bin/bash
# Riparazione filesystem su partizione smontata (equivalenti fsck / chkdsk).

# shellcheck disable=SC1091
. /usr/local/bin/quelo-fs.sh

quelo_fs_repair_supported() {
  local fstype
  fstype="$(quelo_fs_normalize_type "$1")"
  case "${fstype}" in
    ntfs|ext2|ext3|ext4|xfs|btrfs|vfat|exfat) return 0 ;;
    *) return 1 ;;
  esac
}

quelo_fs_repair_tool_name() {
  local fstype mode="${2:-full}"
  fstype="$(quelo_fs_normalize_type "$1")"
  case "${fstype}" in
    ntfs)
      if [[ "${mode}" == "quick" ]]; then
        echo "ntfsfix"
      else
        echo "ntfsfix + badblocks"
      fi
      ;;
    ext2|ext3|ext4) echo "e2fsck" ;;
    xfs)   echo "xfs_repair" ;;
    btrfs) echo "btrfs check" ;;
    vfat)  echo "fsck.vfat" ;;
    exfat) echo "fsck.exfat" ;;
    *)     echo "?" ;;
  esac
}

quelo_fs_repair_is_mounted() {
  local part="$1"
  findmnt -n "${part}" >/dev/null 2>&1
}

quelo_fs_repair_ntfs_quick() {
  local part="$1"

  echo "=== ntfsfix (equivalente chkdsk /f, senza scansione settori) ==="
  command -v ntfsfix >/dev/null 2>&1 || { echo "ntfsfix non disponibile"; return 1; }
  ntfsfix -d "${part}"
}

quelo_fs_repair_ntfs() {
  local part="$1" rc=0

  quelo_fs_repair_ntfs_quick "${part}" || rc=$?

  echo ""
  echo "=== badblocks -sv (scansione settori, equivalente chkdsk /r) ==="
  if command -v badblocks >/dev/null 2>&1; then
    badblocks -sv "${part}" || true
  else
    echo "badblocks non disponibile (solo ntfsfix eseguito)"
  fi

  return "${rc}"
}

quelo_fs_repair_ext() {
  local part="$1"

  command -v e2fsck >/dev/null 2>&1 || { echo "e2fsck non disponibile"; return 1; }
  echo "=== e2fsck -f -y -c (controllo e settori bad) ==="
  e2fsck -f -y -c "${part}"
}

quelo_fs_repair_xfs() {
  local part="$1"

  command -v xfs_repair >/dev/null 2>&1 || { echo "xfs_repair non disponibile"; return 1; }
  echo "=== xfs_repair ==="
  xfs_repair "${part}"
}

quelo_fs_repair_btrfs() {
  local part="$1" rc

  command -v btrfs >/dev/null 2>&1 || { echo "btrfs non disponibile"; return 1; }
  echo "=== btrfs check ==="
  if btrfs check "${part}"; then
    return 0
  fi
  echo "=== btrfs check --repair ==="
  btrfs check --repair "${part}"
}

quelo_fs_repair_vfat() {
  local part="$1"

  if command -v fsck.vfat >/dev/null 2>&1; then
    echo "=== fsck.vfat ==="
    fsck.vfat -a -w "${part}"
  elif command -v fsck.fat >/dev/null 2>&1; then
    echo "=== fsck.fat ==="
    fsck.fat -a -w "${part}"
  else
    echo "fsck.vfat non disponibile"
    return 1
  fi
}

quelo_fs_repair_exfat() {
  local part="$1"

  command -v fsck.exfat >/dev/null 2>&1 || { echo "fsck.exfat non disponibile"; return 1; }
  echo "=== fsck.exfat ==="
  fsck.exfat -y "${part}"
}

quelo_fs_repair_run() {
  local part="$1" mode="${2:-full}" fstype

  [[ -b "${part}" ]] || return 1
  quelo_fs_repair_is_mounted "${part}" && return 2

  fstype="$(quelo_fs_detect "${part}")" || fstype=""
  if [[ -z "${fstype}" ]] && quelo_fs_is_ntfs "${part}"; then
    fstype="ntfs"
  fi
  fstype="$(quelo_fs_normalize_type "${fstype}")"
  quelo_fs_repair_supported "${fstype}" || return 3

  case "${fstype}" in
    ntfs)
      if [[ "${mode}" == "quick" ]]; then
        quelo_fs_repair_ntfs_quick "${part}"
      else
        quelo_fs_repair_ntfs "${part}"
      fi
      ;;
    ext2|ext3|ext4) quelo_fs_repair_ext "${part}" ;;
    xfs)   quelo_fs_repair_xfs "${part}" ;;
    btrfs) quelo_fs_repair_btrfs "${part}" ;;
    vfat)  quelo_fs_repair_vfat "${part}" ;;
    exfat) quelo_fs_repair_exfat "${part}" ;;
    *)     return 3 ;;
  esac

  quelo_block_disk_rescan "$(quelo_partition_disk "${part}")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  part="${1:-}"
  mode="${2:-full}"
  [[ -n "${part}" ]] || exit 1
  [[ "${part}" == /dev/* ]] || part="/dev/${part}"
  quelo_fs_repair_run "${part}" "${mode}"
  exit $?
fi
