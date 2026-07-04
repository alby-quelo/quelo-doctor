#!/bin/bash
set -euo pipefail

SORGENTI="$(cd "$(dirname "$0")" && pwd)"
DOTTORE="$(cd "${SORGENTI}/.." && pwd)"
# Build FUORI dal progetto: Cursor/GVFS non devono toccare il chroot
LB_DIR="/var/tmp/quelo-doctor-live-build"
VERSION_FILE="${SORGENTI}/VERSION"
LOG="${DOTTORE}/.build/build.log"
BUILD_USER="${SUDO_USER:-${USER:-root}}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Esegui come root: sudo $0"
  exit 1
fi

if [[ ! -f "${VERSION_FILE}" ]]; then
  echo "0.01" >"${VERSION_FILE}"
fi

VERSION="$(tr -d '[:space:]' <"${VERSION_FILE}")"
OUTPUT_ISO="${DOTTORE}/ISO/quelo-doctor-${VERSION}-alpha.iso"
VERSION_HISTORY="${SORGENTI}/VERSION_HISTORY"
LAST_BUILT_FILE="${SORGENTI}/LAST_BUILT_VERSION"
PREVIOUS_BUILT_FILE="${SORGENTI}/PREVIOUS_BUILT_VERSION"
ROLLBACK_FILE="${DOTTORE}/ISO/ROLLBACK.txt"

quelo_record_build_version() {
  local built="$1" old_last prev_iso

  old_last=""
  [[ -f "${LAST_BUILT_FILE}" ]] && old_last="$(tr -d '[:space:]' <"${LAST_BUILT_FILE}")"

  echo "${built}" >"${LAST_BUILT_FILE}"
  if [[ -n "${old_last}" && "${old_last}" != "${built}" ]]; then
    echo "${old_last}" >"${PREVIOUS_BUILT_FILE}"
  fi

  if [[ ! -f "${VERSION_HISTORY}" ]]; then
    printf '%s\n' \
      "# Quelo Doctor - storico ISO (piu recente in basso)" \
      "# formato: versione | data build | file ISO | note" \
      >"${VERSION_HISTORY}"
  fi
  printf '%s | %s | %s | build OK\n' \
    "${built}" "$(date -Iseconds)" "$(basename "${OUTPUT_ISO}")" >>"${VERSION_HISTORY}"

  mkdir -p "${DOTTORE}/ISO"
  ln -sfn "$(basename "${OUTPUT_ISO}")" "${DOTTORE}/ISO/latest.iso"
  if [[ -n "${old_last}" && "${old_last}" != "${built}" ]]; then
    prev_iso="quelo-doctor-${old_last}-alpha.iso"
    if [[ -f "${DOTTORE}/ISO/${prev_iso}" ]]; then
      ln -sfn "${prev_iso}" "${DOTTORE}/ISO/previous.iso"
    fi
  fi

  {
    echo "# Generato automaticamente da build.sh - non editare a mano"
    echo "CURRENT_VERSION=${built}"
    echo "CURRENT_ISO=${OUTPUT_ISO}"
    echo "PREVIOUS_VERSION=${old_last:-unknown}"
    if [[ -n "${old_last}" ]]; then
      echo "PREVIOUS_ISO=${DOTTORE}/ISO/quelo-doctor-${old_last}-alpha.iso"
    fi
    next_ver="$(awk -v v="${built}" 'BEGIN { printf "%.2f", v + 0.01 }')"
    echo "NEXT_BUILD_VERSION=${next_ver}"
    echo "BUILT_AT=$(date -Iseconds)"
  } >"${ROLLBACK_FILE}"

  chown "${BUILD_USER}:${BUILD_USER}" \
    "${LAST_BUILT_FILE}" "${PREVIOUS_BUILT_FILE}" "${VERSION_HISTORY}" \
    "${ROLLBACK_FILE}" 2>/dev/null || true
}

quelo_safe_umount() {
  local mp="$1"
  local lb_real mp_real

  lb_real="$(realpath "${LB_DIR}" 2>/dev/null)" || return 0
  mp_real="$(realpath "${mp}" 2>/dev/null)" || return 0
  [[ "${mp_real}" == "${lb_real}/"* ]] || return 0
  mountpoint -q "${mp}" 2>/dev/null || return 0
  umount -l "${mp}" 2>/dev/null || true
}

quelo_cleanup_build() {
  local chroot="${LB_DIR}/chroot"
  [[ -d "${chroot}" ]] || return 0

  echo "Smonto mount live-build (solo lazy umount, sicuro)..."
  for _ in 1 2 3; do
    for mp in \
      "${chroot}/proc/sys/fs/binfmt_misc" \
      "${chroot}/proc" \
      "${chroot}/sys" \
      "${chroot}/dev/pts" \
      "${chroot}/dev/shm" \
      "${chroot}/dev" \
      "${chroot}/run"
    do
      quelo_safe_umount "${mp}"
    done
    sleep 1
  done
}

quelo_build_still_mounted() {
  mount | grep -qF "${LB_DIR}/"
}

OLD_LB_DIR="${DOTTORE}/.build/live-build"

quelo_umount_stray_iso() {
  local mp

  for mp in \
    /media/"${BUILD_USER}"/QUELO-DOCTOR-* \
    /run/media/"${BUILD_USER}"/QUELO-DOCTOR-* \
    /media/"${BUILD_USER}"/quelo-doctor-* \
    /run/media/"${BUILD_USER}"/quelo-doctor-*
  do
    [[ -e "${mp}" ]] || continue
    mountpoint -q "${mp}" 2>/dev/null || continue
    echo "Smonto mount ISO spuri: ${mp}"
    umount "${mp}" 2>/dev/null || umount -l "${mp}" 2>/dev/null || true
  done
}

quelo_cleanup_old_project_build() {
  local chroot="${OLD_LB_DIR}/chroot" mp

  [[ -d "${chroot}" ]] || mount | grep -qF "${OLD_LB_DIR}/" || return 0

  echo "Pulizia vecchia build nel progetto (${OLD_LB_DIR})..."
  for _ in 1 2 3; do
    for mp in \
      "${chroot}/proc/sys/fs/binfmt_misc" \
      "${chroot}/proc" \
      "${chroot}/sys" \
      "${chroot}/dev/pts" \
      "${chroot}/dev/shm" \
      "${chroot}/dev" \
      "${chroot}/run"
    do
      mountpoint -q "${mp}" 2>/dev/null || continue
      umount -l "${mp}" 2>/dev/null || true
    done
    sleep 1
  done

  if mount | grep -qF "${OLD_LB_DIR}/"; then
    echo "ERRORE: mount attivi sotto ${OLD_LB_DIR}. Esegui: sudo ${SORGENTI}/cleanup.sh"
    return 1
  fi

  rm -rf "${OLD_LB_DIR}"
}

mkdir -p "${DOTTORE}/.build" "${DOTTORE}/ISO"
exec > >(tee -a "${LOG}") 2>&1

echo "=== BUILD $(date -Iseconds) versione ${VERSION} ==="
echo "Build dir: ${LB_DIR}"

quelo_umount_stray_iso
quelo_cleanup_old_project_build || exit 1

missing=()
for cmd in lb debootstrap mksquashfs xorriso; do
  command -v "$cmd" >/dev/null || missing+=("$cmd")
done

if ((${#missing[@]})); then
  apt-get update
  apt-get install -y live-build debootstrap squashfs-tools xorriso rsync
fi

quelo_cleanup_build
if quelo_build_still_mounted; then
  echo ""
  echo "ERRORE: mount live-build ancora attivi."
  echo "Esegui dopo un riavvio, oppure: sudo ./cleanup.sh"
  exit 1
fi

rm -rf "${LB_DIR}"
mkdir -p "${LB_DIR}/config/includes.chroot" \
  "${LB_DIR}/config/includes.binary" \
  "${LB_DIR}/config/hooks/normal"

cd "${LB_DIR}"

lb config \
  --distribution sid \
  --archive-areas "main contrib non-free non-free-firmware" \
  --linux-flavours amd64 \
  --linux-packages "linux-image" \
  --bootappend-live "boot=live components username=root locales=it_IT.UTF-8 console=tty1" \
  --debian-installer none \
  --iso-application "Quelo Doctor ${VERSION} alpha" \
  --iso-volume "QUELO-DOCTOR-${VERSION}" \
  --memtest none \
  --win32-loader false \
  --apt-recommends false \
  --security false \
  --updates false \
  --backports false \
  --firmware-binary false \
  --firmware-chroot false \
  --initramfs live-boot \
  --initramfs-compression gzip \
  --chroot-squashfs-compression-type zstd \
  --initsystem systemd

cp -a "${SORGENTI}/overlay/." "${LB_DIR}/config/includes.chroot/"
mkdir -p "${LB_DIR}/config/includes.chroot/etc"
echo "${VERSION}" >"${LB_DIR}/config/includes.chroot/etc/quelo-doctor-version"
echo "${VERSION}" >"${LB_DIR}/config/includes.binary/quelo-version"

for hook in "${SORGENTI}/hooks/"*.chroot "${SORGENTI}/hooks/"*.binary; do
  [[ -f "${hook}" ]] || continue
  cp "${hook}" "${LB_DIR}/config/hooks/normal/"
  chmod +x "${LB_DIR}/config/hooks/normal/$(basename "${hook}")"
done

if [[ -f "${SORGENTI}/packages/extra.list.chroot" ]]; then
  cat "${SORGENTI}/packages/extra.list.chroot" >>"${LB_DIR}/config/package-lists/live.list.chroot"
fi

echo "Output: ${OUTPUT_ISO}"
if ! lb build; then
  echo ""
  echo "ERRORE: lb build fallita."
  echo "Se serve pulizia: sudo ./cleanup.sh (meglio dopo riavvio se il desktop è instabile)"
  exit 1
fi

ISO="$(find "${LB_DIR}" -name '*.iso' -type f 2>/dev/null | head -1)"

if [[ -z "${ISO}" || ! -f "${ISO}" ]]; then
  echo "ERRORE: ISO non generata. Log: ${LOG}"
  exit 1
fi

NEXT_VERSION="$(awk -v v="${VERSION}" 'BEGIN { printf "%.2f", v + 0.01 }')"

cp -f "${ISO}" "${OUTPUT_ISO}"
chown "${BUILD_USER}:${BUILD_USER}" "${OUTPUT_ISO}" 2>/dev/null || true

if ! quelo_record_build_version "${VERSION}"; then
  echo ""
  echo "AVVISO: registro versione fallito (controlla encoding in build.sh). ISO copiata comunque."
fi

echo "${NEXT_VERSION}" >"${VERSION_FILE}"
chown "${BUILD_USER}:${BUILD_USER}" "${VERSION_FILE}" \
  "${LAST_BUILT_FILE}" "${PREVIOUS_BUILT_FILE}" "${VERSION_HISTORY}" \
  "${ROLLBACK_FILE}" 2>/dev/null || true

quelo_umount_stray_iso

echo ""
echo "ISO PRONTA: ${OUTPUT_ISO}"
echo "Prossima versione: ${NEXT_VERSION}"
if [[ -f "${PREVIOUS_BUILT_FILE}" ]]; then
  echo "Rollback:   ${DOTTORE}/ISO/previous.iso (v$(tr -d '[:space:]' <"${PREVIOUS_BUILT_FILE}"))"
fi
echo "Storico:    ${SORGENTI}/show-versions.sh"
echo "Se automount OK su hardware: ${SORGENTI}/mark-known-good.sh ${VERSION}"
