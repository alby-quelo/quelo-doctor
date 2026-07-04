#!/bin/bash
# Elenco versioni ISO e puntatori per rollback.

SORGENTI="$(cd "$(dirname "$0")" && pwd)"
DOTTORE="$(cd "${SORGENTI}/.." && pwd)"
ISO_DIR="${DOTTORE}/ISO"

next="$(tr -d '[:space:]' <"${SORGENTI}/VERSION" 2>/dev/null || echo "?")"
last="$(tr -d '[:space:]' <"${SORGENTI}/LAST_BUILT_VERSION" 2>/dev/null || echo "-")"
prev="$(tr -d '[:space:]' <"${SORGENTI}/PREVIOUS_BUILT_VERSION" 2>/dev/null || echo "-")"
known_auto="$(grep -v '^#' "${SORGENTI}/KNOWN_GOOD_AUTOMOUNT" 2>/dev/null | head -1 | tr -d '[:space:]')"

echo "=== Quelo Doctor — versioni ISO ==="
echo ""
echo "Prossima build:     ${next}"
echo "Ultima build OK:    ${last}  →  quelo-doctor-${last}-alpha.iso"
echo "Precedente:         ${prev}  →  quelo-doctor-${prev}-alpha.iso"
if [[ -n "${known_auto}" ]]; then
  echo "Automount OK:       ${known_auto}  →  quelo-doctor-${known_auto}-alpha.iso  (rollback automount)"
  echo "                    Aggiorna dopo test: ./mark-known-good.sh [versione]"
fi
echo ""

if [[ -L "${ISO_DIR}/latest.iso" ]]; then
  echo "Symlink latest:   $(readlink -f "${ISO_DIR}/latest.iso" 2>/dev/null || readlink "${ISO_DIR}/latest.iso")"
fi
if [[ -L "${ISO_DIR}/previous.iso" ]]; then
  echo "Symlink previous: $(readlink -f "${ISO_DIR}/previous.iso" 2>/dev/null || readlink "${ISO_DIR}/previous.iso")"
fi
echo ""

if [[ -f "${ISO_DIR}/ROLLBACK.txt" ]]; then
  echo "--- ROLLBACK.txt ---"
  grep -v '^#' "${ISO_DIR}/ROLLBACK.txt" | sed '/^$/d'
  echo ""
fi

echo "--- ISO in ${ISO_DIR} ---"
if compgen -G "${ISO_DIR}/"*.iso >/dev/null 2>&1; then
  ls -lhS "${ISO_DIR}/"*.iso 2>/dev/null
else
  echo "(nessuna ISO presente)"
fi
echo ""

if [[ -f "${SORGENTI}/VERSION_HISTORY" ]]; then
  echo "--- Storico (VERSION_HISTORY) ---"
  grep -v '^#' "${SORGENTI}/VERSION_HISTORY" | grep -v '^$' | tail -15
fi
