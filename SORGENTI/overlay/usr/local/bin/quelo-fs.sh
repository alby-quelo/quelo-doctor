#!/bin/bash
# Rilevamento filesystem e risoluzione partizioni (blkid, lsblk, ntfs-3g.probe).

quelo_fs_probe_device() {
  local dev="$1"
  [[ -n "${dev}" && -b "${dev}" ]] || return 1
  blkid "${dev}" >/dev/null 2>&1 || true
  blkid -p "${dev}" >/dev/null 2>&1 || true
}

quelo_live_disk() {
  local src dev pk disk back

  for src in /run/live/medium /lib/live/mount/medium; do
    mountpoint -q "${src}" 2>/dev/null || continue
    dev="$(findmnt -n -o SOURCE -T "${src}" 2>/dev/null)" || continue
    dev="$(quelo_partition_resolve "${dev}" 2>/dev/null)" || continue

    if [[ "${dev}" == /dev/loop* ]] && command -v losetup >/dev/null 2>&1; then
      back="$(losetup -n -O BACK-FILE "${dev}" 2>/dev/null)" || back=""
      if [[ -n "${back}" ]]; then
        dev="$(findmnt -n -o SOURCE -T "$(dirname "${back}")" 2>/dev/null)" || dev=""
        dev="$(quelo_partition_resolve "${dev}" 2>/dev/null)" || dev=""
      fi
    fi

    [[ -n "${dev}" ]] || continue
    disk="$(quelo_partition_disk "${dev}")"
    [[ -n "${disk}" ]] && { echo "${disk}"; return 0; }
  done
  return 1
}

quelo_live_is_on_disk() {
  local dev="$1" live disk

  live="$(quelo_live_disk 2>/dev/null)" || return 1
  disk="$(quelo_partition_disk "${dev}")"
  [[ "${disk}" == "${live}" ]]
}

quelo_live_is_medium_partition() {
  local dev="$1" src mp resolved part

  part="$(quelo_partition_resolve "${dev}" 2>/dev/null)" || part="${dev}"
  for mp in /run/live/medium /lib/live/mount/medium; do
    mountpoint -q "${mp}" 2>/dev/null || continue
    src="$(quelo_fs_mount_source "${mp}")" || src=""
    resolved="$(quelo_partition_resolve "${src}" 2>/dev/null)" || resolved="${src}"
    [[ -n "${resolved}" && "${resolved}" == "${part}" ]] && return 0
  done
  return 1
}

quelo_partition_resolve() {
  local spec="$1" dev id

  [[ -n "${spec}" ]] || return 1
  spec="${spec#*(}"

  case "${spec}" in
    /dev/*)
      readlink -f "${spec}" 2>/dev/null || echo "${spec}"
      return 0
      ;;
    UUID=*)
      id="${spec#UUID=}"
      dev="$(readlink -f "/dev/disk/by-uuid/${id}" 2>/dev/null)" || \
        dev="$(blkid -U "${id}" 2>/dev/null)"
      ;;
    LABEL=*)
      id="${spec#LABEL=}"
      dev="$(readlink -f "/dev/disk/by-label/${id}" 2>/dev/null)" || \
        dev="$(blkid -L "${id}" 2>/dev/null)"
      ;;
    PARTUUID=*)
      id="${spec#PARTUUID=}"
      dev="$(readlink -f "/dev/disk/by-partuuid/${id}" 2>/dev/null)"
      ;;
    PARTLABEL=*)
      id="${spec#PARTLABEL=}"
      dev="$(readlink -f "/dev/disk/by-partlabel/${id}" 2>/dev/null)"
      ;;
    *)
      if [[ -b "/dev/${spec}" ]]; then
        readlink -f "/dev/${spec}" 2>/dev/null || echo "/dev/${spec}"
        return 0
      fi
      dev="$(findmnt -n -o SOURCE --source "${spec}" 2>/dev/null)" || dev=""
      ;;
  esac

  [[ -n "${dev}" && -b "${dev}" ]] && echo "${dev}"
}

quelo_partition_disk() {
  local part="$1" pk resolved

  resolved="$(quelo_partition_resolve "${part}" 2>/dev/null)" || resolved="${part}"
  [[ "${resolved}" == /dev/* ]] || resolved="/dev/${resolved}"
  pk="$(lsblk -no PKNAME "${resolved}" 2>/dev/null)" || pk=""
  if [[ -n "${pk}" ]]; then
    echo "/dev/${pk}"
  else
    echo "${resolved}"
  fi
}

quelo_partition_belongs_disk() {
  local part="$1" disk="$2"

  [[ -n "${part}" && -n "${disk}" ]] || return 1
  [[ "$(quelo_partition_disk "${part}")" == "${disk}" ]]
}

# Stesso schema dell'automount (lsblk NAME,TYPE): evita SIZE con spazi che rompe awk.
# Usare -ln: senza -l lsblk aggiunge prefissi albero (└─/dev/sdb1) e -b fallisce.
quelo_lsblk_clean_name() {
  local spec="$1"
  spec="${spec#"${spec%%[![:space:]]*}"}"
  if [[ "${spec}" == *"/dev/"* ]]; then
    echo "/dev/${spec##*/dev/}"
  else
    echo "${spec}"
  fi
}

quelo_disk_enum_partitions() {
  local disk="$1" part found=0

  [[ -n "${disk}" ]] || return 0

  while IFS= read -r part; do
    [[ -n "${part}" ]] || continue
    part="$(quelo_lsblk_clean_name "${part}")"
    [[ -b "${part}" ]] || continue
    found=1
    echo "${part}"
  done < <(lsblk -ln -p -o NAME,TYPE "${disk}" 2>/dev/null | awk '$2=="part" {print $1}')
  ((found)) && return 0

  while IFS= read -r part; do
    [[ -n "${part}" ]] || continue
    part="$(quelo_lsblk_clean_name "${part}")"
    [[ -b "${part}" ]] || continue
    quelo_partition_belongs_disk "${part}" "${disk}" || continue
    echo "${part}"
  done < <(lsblk -ln -p -o NAME,TYPE 2>/dev/null | awk '$2=="part" {print $1}')
}

# Solo aggiornamento cache blkid (sicuro durante menu).
quelo_block_disk_probe() {
  local disk="$1" part

  [[ -n "${disk}" && -b "${disk}" ]] || return 0
  while IFS= read -r part; do
    [[ -n "${part}" ]] || continue
    quelo_fs_probe_device "${part}" || true
  done < <(quelo_disk_enum_partitions "${disk}")
}

# Dopo fsck: partprobe + blkid (non usare dopo umount manuale).
quelo_block_disk_rescan() {
  local disk="$1"

  [[ -n "${disk}" && -b "${disk}" ]] || return 0

  if command -v blockdev >/dev/null 2>&1; then
    blockdev --flushbufs "${disk}" 2>/dev/null || true
  fi
  if command -v partprobe >/dev/null 2>&1; then
    partprobe "${disk}" 2>/dev/null || partprobe -s "${disk}" 2>/dev/null || true
  fi
  if command -v udevadm >/dev/null 2>&1; then
    udevadm settle --timeout=5 2>/dev/null || true
  fi
  quelo_block_disk_probe "${disk}"
}

quelo_fs_normalize_type() {
  case "${1,,}" in
    ntfs|ntfs-3g|ntfs3|fuseblk) echo "ntfs" ;;
    msdos|vfat|fat|fat32) echo "vfat" ;;
    crypto_luks) echo "crypto_luks" ;;
    bitlocker) echo "bitlocker" ;;
    "") echo "" ;;
    *) echo "${1,,}" ;;
  esac
}

quelo_fs_detect() {
  local dev="$1" resolved fstype

  resolved="$(quelo_partition_resolve "${dev}" 2>/dev/null)" || resolved="${dev}"
  [[ -b "${resolved}" ]] || return 1

  quelo_fs_probe_device "${resolved}" || true

  fstype="$(blkid -o value -s TYPE "${resolved}" 2>/dev/null)" || fstype=""
  if [[ -z "${fstype}" ]]; then
    fstype="$(lsblk -no FSTYPE "${resolved}" 2>/dev/null | head -1 | tr -d '[:space:]')" || fstype=""
  fi
  if [[ -z "${fstype}" ]]; then
    fstype="$(blkid -p -o value -s TYPE "${resolved}" 2>/dev/null)" || fstype=""
  fi
  if [[ -z "${fstype}" ]] && command -v ntfs-3g.probe >/dev/null 2>&1; then
    if ntfs-3g.probe --readonly "${resolved}" >/dev/null 2>&1; then
      fstype="ntfs"
    fi
  fi

  fstype="$(quelo_fs_normalize_type "${fstype}")"
  [[ -n "${fstype}" ]] && echo "${fstype}"
}

quelo_fs_is_ntfs() {
  local dev="$1" resolved fstype pt

  resolved="$(quelo_partition_resolve "${dev}" 2>/dev/null)" || resolved="${dev}"
  [[ -b "${resolved}" ]] || return 1

  fstype="$(quelo_fs_detect "${resolved}")"
  [[ "${fstype}" == "ntfs" ]] && return 0

  pt="$(lsblk -no PARTTYPENAME "${resolved}" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  [[ "${pt}" == *microsoft*basic* ]] && return 0

  if command -v ntfs-3g.probe >/dev/null 2>&1; then
    quelo_fs_probe_device "${resolved}" || true
    ntfs-3g.probe --readonly "${resolved}" >/dev/null 2>&1 && return 0
  fi
  return 1
}

quelo_fs_should_skip_mount() {
  local fstype
  fstype="$(quelo_fs_normalize_type "$1")"
  case "${fstype}" in
    swap|crypto_luks|bitlocker) return 0 ;;
    iso9660|udf|squashfs|erofs|overlay|aufs|tmpfs) return 0 ;;
    "") return 1 ;;
    *) return 1 ;;
  esac
}

quelo_fs_mount_source() {
  local mp="$1"
  findmnt -n -o SOURCE "${mp}" 2>/dev/null
}

# File esportati su USB/disco esterno: leggibili dal primo utente desktop (uid 1000).
quelo_fs_publish_export() {
  local path="$1"

  [[ -f "${path}" ]] || return 1
  chmod 0644 "${path}" 2>/dev/null || true
  chown 1000:1000 "${path}" 2>/dev/null || true
  return 0
}
