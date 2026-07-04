quelo_mc_is_en() {
  [[ -f /etc/default/locale ]] && grep -qE '^LANG=en_' /etc/default/locale
}

quelo_mc_show_help() {
  local title body

  if quelo_mc_is_en; then
    title="FILE MANAGER (mc)"
    body="NAVIGATION
  Arrows     move
  Tab        switch left/right panel
  Alt+F1/F2  drive list (left/right panel)
  Enter      enter folder

TOP MENU (File, Commands, Options...)
  Esc+9 or F9   open menu bar
  Arrows        move between menus and items
  Enter         select

COPY / MOVE / DELETE
  Esc+3 or F3   view file
  Esc+5 or F5   copy to other panel
  Esc+6 or F6   move (rename)
  Esc+8 or F8   delete (confirmation)
  Esc+4 or F4   edit file (vim)

EXIT
  Esc+0 or F10  quit mc

QEMU / HOST PC
  F-keys may reach the host, not the VM.
  Use Esc+number instead (e.g. Esc+9 = menu).
  In QEMU menu: Ctrl+Alt+G captures keyboard.

Press OK to open mc."
  else
    title="GESTIONE FILE (mc)"
    body="NAVIGAZIONE
  Frecce     spostamento
  Tab        cambia pannello sinistro/destro
  Alt+F1/F2  elenco dischi (pannello sx/dx)
  Invio      entra nella cartella

MENU IN ALTO (File, Comandi, Opzioni...)
  Esc+9 o F9   apre il menu
  Frecce       tra voci e sottomenu
  Invio        seleziona

COPIA / SPOSTA / ELIMINA
  Esc+3 o F3   visualizza file
  Esc+5 o F5   copia nell'altro pannello
  Esc+6 o F6   sposta (rinomina)
  Esc+8 o F8   elimina (con conferma)
  Esc+4 o F4   modifica file (vim)

USCITA
  Esc+0 o F10  esci da mc

QEMU / PC HOST
  I tasti F possono andare al PC, non alla VM.
  Usa Esc+numero (es. Esc+9 = menu).
  Nel menu QEMU: Ctrl+Alt+G cattura la tastiera.

Premi OK per aprire mc."
  fi

  if command -v dialog >/dev/null 2>&1; then
    dialog --clear --backtitle "Quelo Doctor" --title "${title}" \
      --msgbox "${body}" 26 72 </dev/tty 2>/dev/null || true
  else
    printf '%s\n\n' "${body}"
    read -r -n 1 -s _ </dev/tty 2>/dev/null || true
  fi
}

quelo_mc_prepare() {
  mkdir -p /media /root/.config/mc /root/.local/share/mc/skins

  if [[ -f /usr/share/mc/skins/quelo-doctor.ini ]]; then
    cp /usr/share/mc/skins/quelo-doctor.ini /root/.local/share/mc/skins/quelo-doctor.ini
  elif [[ -f /etc/mc/skins/quelo-doctor.ini ]]; then
    cp /etc/mc/skins/quelo-doctor.ini /root/.local/share/mc/skins/quelo-doctor.ini
  fi

  if [[ -f /etc/mc/mc.ini ]]; then
    cp /etc/mc/mc.ini /root/.config/mc/ini
  fi

  if [[ -f /root/.config/mc/ini ]]; then
    if grep -q '^skin=' /root/.config/mc/ini; then
      sed -i 's/^skin=.*/skin=quelo-doctor/' /root/.config/mc/ini
    else
      printf '\nskin=quelo-doctor\n' >>/root/.config/mc/ini
    fi
    sed -i 's/^auto_save_setup=.*/auto_save_setup=false/' /root/.config/mc/ini
    sed -i 's/^message_visible=.*/message_visible=0/' /root/.config/mc/ini
    grep -q '^message_visible=' /root/.config/mc/ini || \
      printf '\nmessage_visible=0\n' >>/root/.config/mc/ini
  fi

  if [[ -f /etc/mc/hints/mc.hint ]]; then
    mkdir -p /root/.config/mc/hints
    cp /etc/mc/hints/mc.hint /root/.config/mc/hints/mc.hint 2>/dev/null || true
  fi
}
