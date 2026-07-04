#!/bin/bash
# Silenzia messaggi kernel/console per menu e app a schermo intero.
# I messaggi tornano visibili solo nella shell (menu 1).

QUELO_CONSOLE_QUIET_PRINTK_FILE=/run/quelo-console-printk-saved
QUELO_CONSOLE_QUIET_ACTIVE_FILE=/run/quelo-console-quiet-active
QUELO_CONSOLE_QUIET_SHELL_PRINTK='7 4 1 7'
QUELO_CONSOLE_QUIET_MENU_PRINTK='1 4 1 1'

quelo_console_quiet_on() {
  if [[ -r /proc/sys/kernel/printk && ! -f "${QUELO_CONSOLE_QUIET_PRINTK_FILE}" ]]; then
    cat /proc/sys/kernel/printk > "${QUELO_CONSOLE_QUIET_PRINTK_FILE}" 2>/dev/null || true
  fi
  if [[ -w /proc/sys/kernel/printk ]]; then
    echo "${QUELO_CONSOLE_QUIET_MENU_PRINTK}" > /proc/sys/kernel/printk 2>/dev/null || true
  fi
  if [[ ! -f "${QUELO_CONSOLE_QUIET_ACTIVE_FILE}" ]] && command -v setterm >/dev/null 2>&1; then
    if setterm -msg off </dev/tty >/dev/tty 2>/dev/null \
      || setterm --msg off </dev/tty >/dev/tty 2>/dev/null; then
      : > "${QUELO_CONSOLE_QUIET_ACTIVE_FILE}"
    fi
  fi
}

quelo_console_quiet_off() {
  if [[ -f "${QUELO_CONSOLE_QUIET_ACTIVE_FILE}" ]] && command -v setterm >/dev/null 2>&1; then
    setterm -msg on </dev/tty >/dev/tty 2>/dev/null \
      || setterm --msg on </dev/tty >/dev/tty 2>/dev/null \
      || true
    rm -f "${QUELO_CONSOLE_QUIET_ACTIVE_FILE}"
  elif command -v setterm >/dev/null 2>&1; then
    setterm -msg on </dev/tty >/dev/tty 2>/dev/null \
      || setterm --msg on </dev/tty >/dev/tty 2>/dev/null \
      || true
  fi
  if [[ -w /proc/sys/kernel/printk ]]; then
    echo "${QUELO_CONSOLE_QUIET_SHELL_PRINTK}" > /proc/sys/kernel/printk 2>/dev/null || true
  fi
  rm -f "${QUELO_CONSOLE_QUIET_PRINTK_FILE}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    on)  quelo_console_quiet_on ;;
    off) quelo_console_quiet_off ;;
  esac
fi
