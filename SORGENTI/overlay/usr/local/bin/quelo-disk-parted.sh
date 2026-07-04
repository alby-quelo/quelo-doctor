#!/bin/bash
# Operazioni distruttive su disco/partizione (parted + mkfs).

# shellcheck disable=SC1091
. /usr/local/bin/quelo-fs.sh

quelo_parted_is_live_disk() {
  local disk="$1" live
  live="$(quelo_live_disk 2>/dev/null)" || return 1
  [[ "${disk}" == "${live}" ]]
}

quelo_parted_part_number() {
  local disk="$1" part="$2" n dev

  part="$(quelo_partition_resolve "${part}" 2>/dev/null)" || part="${part}"
  command -v parted >/dev/null 2>&1 || return 1

  while IFS= read -r n; do
    [[ -n "${n}" ]] || continue
    dev="$(quelo_disk_parted_minor_to_dev "${disk}" "${n}")"
    [[ "${dev}" == "${part}" ]] && { echo "${n}"; return 0; }
  done < <(parted -s "${disk}" unit s print 2>/dev/null | awk '/^ *[0-9]+/ {print $1}')
  return 1
}

quelo_disk_parted_minor_to_dev() {
  local disk="$1" minor="$2"
  if [[ "${disk}" == /dev/nvme* || "${disk}" == /dev/mmcblk* ]]; then
    echo "${disk}p${minor}"
  else
    echo "${disk}${minor}"
  fi
}

quelo_parted_umount_part() {
  local part="$1" mp

  part="$(quelo_partition_resolve "${part}" 2>/dev/null)" || part="${part}"
  mp="$(findmnt -n -o TARGET --source "${part}" 2>/dev/null)" || mp=""
  [[ -n "${mp}" ]] || return 0
  umount "${mp}" 2>/dev/null || umount -l "${mp}" 2>/dev/null || return 1
  /usr/local/bin/quelo-automount remove "${part##*/}" 2>/dev/null || true
  findmnt -n --source "${part}" >/dev/null 2>&1 && return 1
  return 0
}

quelo_parted_umount_disk() {
  local disk="$1" part

  while IFS= read -r part; do
    [[ -n "${part}" ]] || continue
    quelo_parted_umount_part "${part}" || return 1
  done < <(quelo_disk_enum_partitions "${disk}")
  return 0
}

quelo_parted_free_span() {
  local disk="$1"
  parted -s "${disk}" unit MiB print free 2>/dev/null | awk '
    /Free Space/ {
      if (match($0, /([0-9.]+)MiB[[:space:]]+([0-9.]+)MiB[[:space:]]+([0-9.]+)MiB/, a)) {
        print a[1] "MiB " a[3] "MiB"
        exit
      }
    }'
}

quelo_parted_delete_partition() {
  local disk="$1" part="$2" num

  command -v parted >/dev/null 2>&1 || return 1
  quelo_parted_is_live_disk "${disk}" && return 2
  part="$(quelo_partition_resolve "${part}" 2>/dev/null)" || part="${part}"
  quelo_parted_umount_part "${part}" || return 3
  num="$(quelo_parted_part_number "${disk}" "${part}")" || return 4
  parted -s "${disk}" rm "${num}" || return 5
  quelo_block_disk_rescan "${disk}"
  return 0
}

quelo_parted_create_partition() {
  local disk="$1"

  command -v parted >/dev/null 2>&1 || return 1
  quelo_parted_is_live_disk "${disk}" && return 2
  if ! parted -s "${disk}" mkpart primary 1MiB 100% 2>/dev/null; then
    parted -s "${disk}" mkpart primary 0% 100% || return 3
  fi
  sleep 1
  quelo_block_disk_rescan "${disk}"
  return 0
}

quelo_parted_format_partition() {
  local part="$1" fstype="$2" disk

  part="$(quelo_partition_resolve "${part}" 2>/dev/null)" || part="${part}"
  disk="$(quelo_partition_disk "${part}")"
  quelo_parted_is_live_disk "${disk}" && return 2
  quelo_parted_umount_part "${part}" || return 3

  fstype="$(quelo_fs_normalize_type "${fstype}")"
  case "${fstype}" in
    ntfs)
      command -v mkfs.ntfs >/dev/null 2>&1 || return 4
      mkfs.ntfs -f -L "DATA" "${part}" || return 5
      ;;
    ext4)
      command -v mkfs.ext4 >/dev/null 2>&1 || return 4
      mkfs.ext4 -F "${part}" || return 5
      ;;
    vfat)
      command -v mkfs.vfat >/dev/null 2>&1 || return 4
      mkfs.vfat -F 32 "${part}" || return 5
      ;;
    exfat)
      command -v mkfs.exfat >/dev/null 2>&1 || return 4
      mkfs.exfat -n "DATA" "${part}" || return 5
      ;;
    *) return 4 ;;
  esac
  quelo_block_disk_probe "${disk}"
  return 0
}

quelo_parted_create_table() {
  local disk="$1" label="$2"

  command -v parted >/dev/null 2>&1 || return 1
  quelo_parted_is_live_disk "${disk}" && return 2
  quelo_parted_umount_disk "${disk}" || return 3
  case "${label}" in
    gpt|msdos) ;;
    *) return 4 ;;
  esac
  parted -s "${disk}" mklabel "${label}" || return 5
  sleep 1
  quelo_block_disk_rescan "${disk}"
  return 0
}

quelo_parted_delete_table() {
  local disk="$1"

  command -v parted >/dev/null 2>&1 || return 1
  quelo_parted_is_live_disk "${disk}" && return 2
  quelo_parted_umount_disk "${disk}" || return 3
  wipefs -af "${disk}" 2>/dev/null || true
  sleep 1
  quelo_block_disk_rescan "${disk}"
  return 0
}
