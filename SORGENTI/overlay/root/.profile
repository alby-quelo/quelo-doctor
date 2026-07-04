if [[ "$(tty)" == "/dev/tty1" && -z "${QUELO_IN_SHELL:-}" ]]; then
  /usr/local/bin/quelo-setup-display 2>/dev/null || true
  # shellcheck disable=SC1091
  . /usr/local/bin/quelo-console-quiet.sh
  quelo_console_quiet_on
  exec /usr/local/bin/live-menu
fi
