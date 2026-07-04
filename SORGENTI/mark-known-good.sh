#!/bin/bash
# Segna una versione come ultima ISO con automount (e funzioni) verificate.
# Uso: ./mark-known-good.sh [versione]
# Senza argomento usa LAST_BUILT_VERSION.

set -euo pipefail

SORGENTI="$(cd "$(dirname "$0")" && pwd)"
KNOWN_FILE="${SORGENTI}/KNOWN_GOOD_AUTOMOUNT"
HISTORY="${SORGENTI}/VERSION_HISTORY"
LAST_FILE="${SORGENTI}/LAST_BUILT_VERSION"

ver="${1:-}"
if [[ -z "${ver}" ]]; then
  [[ -f "${LAST_FILE}" ]] || { echo "Manca LAST_BUILT_VERSION; indica la versione: $0 0.45"; exit 1; }
  ver="$(tr -d '[:space:]' <"${LAST_FILE}")"
fi

if [[ ! "${ver}" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "Versione non valida: ${ver}"
  exit 1
fi

{
  echo "${ver}"
  echo "# Ultima ISO verificata OK (automount e uso generale)."
  echo "# File: quelo-doctor-${ver}-alpha.iso"
  echo "# Aggiornato: $(date -Iseconds)"
} >"${KNOWN_FILE}"

if [[ -f "${HISTORY}" ]]; then
  if grep -q "AUTOMOUNT OK - ultima versione buona" "${HISTORY}"; then
    sed -i "s/| AUTOMOUNT OK - ultima versione buona.*/| automount verificato (sostituita da ${ver})/" "${HISTORY}" 2>/dev/null || true
  fi
  if ! grep -q "^${ver} |" "${HISTORY}"; then
    printf '%s | %s | quelo-doctor-%s-alpha.iso | AUTOMOUNT OK - ultima versione buona\n' \
      "${ver}" "$(date -Iseconds)" "${ver}" >>"${HISTORY}"
  else
    sed -i "s|^${ver} |.*|${ver} | $(date -Iseconds) | quelo-doctor-${ver}-alpha.iso | AUTOMOUNT OK - ultima versione buona|" "${HISTORY}" 2>/dev/null || \
      printf '%s | %s | quelo-doctor-%s-alpha.iso | AUTOMOUNT OK - ultima versione buona\n' \
        "${ver}" "$(date -Iseconds)" "${ver}" >>"${HISTORY}"
  fi
fi

echo "Riferimento aggiornato: ${ver} (quelo-doctor-${ver}-alpha.iso)"
echo "Vedi: ./show-versions.sh"
