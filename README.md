<p align="center">
  <img src="images/quelo-mascot.png" alt="Mascotte Quelo" width="160">
</p>

<h1 align="center">Quelo Doctor</h1>

<p align="center">
  <strong>ISO live di soccorso per PC</strong> — menu testuale, diagnostica dischi, recupero dati, antivirus offline.<br>
  <strong>PC rescue live ISO</strong> — text menu, disk diagnostics, data recovery, offline malware scan.
</p>

<p align="center">
  <a href="https://github.com/alby-quelo/quelo-doctor/releases/latest"><img src="https://img.shields.io/github/v/release/alby-quelo/quelo-doctor?label=release" alt="Release"></a>
  <img src="https://img.shields.io/badge/versione%20verificata-0.75-green" alt="Known good 0.75">
  <img src="https://img.shields.io/badge/arch-amd64-blue" alt="amd64">
  <img src="https://img.shields.io/badge/base-Debian%20sid-orange" alt="Debian sid">
</p>

<p align="center">
  <a href="https://alby-quelo.github.io/quelo-doctor/">Sito web / Website</a> ·
  <a href="#download">Download</a> ·
  <a href="#italiano">Italiano</a> ·
  <a href="#english">English</a> ·
  <a href="#build">Build</a> ·
  <a href="#segnalare-problemi">Segnalazioni</a>
</p>

---

<p align="center">
  <img src="images/principale.png" alt="Menu principale Quelo Doctor 0.75" width="800">
</p>
<p align="center"><em>Menu principale — versione 0.75 alpha / Main menu — version 0.75 alpha</em></p>

---

## Download

| File | Descrizione |
|------|-------------|
| **[quelo-doctor-0.75-alpha.iso](https://github.com/alby-quelo/quelo-doctor/releases/latest)** | Ultima ISO verificata (~1 GB) |
| **SORGENTI/** in questo repo | Sorgenti per build e personalizzazione |

> L'ISO non è nel tree git (limite 100 MB di GitHub). Si scarica dalle **Releases**.

**Avvio:** flash su USB (Ventoy, Rufus, balenaEtcher, `dd`) → boot UEFI o Legacy BIOS.

---

<a id="italiano"></a>
## Italiano

### Cos'è Quelo Doctor

**Quelo Doctor** è una distribuzione **live** pensata per tecnici e utenti avanzati che devono **salvare un PC in emergenza**: dischi che non bootano, file cancellati, sospetta infezione, password dimenticate, avvio Windows/Linux rotto.

Niente desktop, niente browser: solo un **menu testuale** rapido su TTY, ispirato al personaggio **Quelo** di Corrado Guzzanti (crediti in menu **C**).

### Perché queste scelte

| Scelta | Motivo |
|--------|--------|
| **Menu testuale, no GUI** | Funziona su quasi tutto l'hardware, anche con GPU/driver problematici; meno RAM, avvio più prevedibile |
| **Debian sid + live-build** | Base solida, pacchetti aggiornati, toolchain standard per ISO live |
| **Un tool per voce di menu** | Flusso guidato: non devi cercare quale programma lanciare (TestDisk, mc, ClamAV…) |
| **Automount USB in /media** | Chiavette e dischi USB compaiono subito, pronti per salvare report e log |
| **Documentazione stile `man`** | Crediti, licenze e manuale (C/M) usano `man-db` + `groff` + `less`: scroll affidabile su console |
| **Tasto Q uniforme** | Indietro/uscita uguale ovunque (sottomenu e testi), come nei pager standard Linux |
| **Solo amd64** | Copre i PC reali in campo; build più snella |

### Menu principale

**PRINCIPALE**
1. Shell root  
2. Controllo dischi (SMART, partizioni, mount, fsck)  
3. Gestione file (Midnight Commander)  
4. Recupera dischi (TestDisk)  
5. Recupera file (ext/NTFS, wizard)  
6. Ripara avvio S.O. (GRUB, MBR, Windows)  
7. Controlla infezioni (ClamAV, YARA, chkrootkit)  
8. Sblocca password e criptazioni *(experimental)*  

**AMBIENTE** — `L` lingua/tastiera · `N` rete  

**INFO** — `C` crediti e licenze · `M` manuale · `S` salva rapporto/log su USB  

**POWER** — `Alt+Z` spegni · `Alt+R` riavvia  

### Software principale incluso

TestDisk/PhotoRec, Midnight Commander, ClamAV, YARA, GRUB, ntfs-3g, NetworkManager, smartmontools, cryptsetup/dislocker, e componenti Debian documentati in menu **C** / **Licenze**.

### Come funziona (in breve)

1. Boot da USB → logo e menu verde/ambra  
2. Un tasto per scegliere la voce  
3. **Q** per tornare indietro  
4. I report (menu **S** e log scan menu **7**) si salvano su supporti esterni con permessi leggibili da desktop (`644`, utente `1000`)  

### Build dalla sorgente

Requisiti: Debian/Ubuntu, `sudo`, `live-build`, `debootstrap`, spazio ~15 GB.

```bash
git clone https://github.com/alby-quelo/quelo-doctor.git
cd quelo-doctor/SORGENTI
sudo ./build.sh
```

L'ISO finisce in `../ISO/quelo-doctor-X.XX-alpha.iso`. Versione corrente in `SORGENTI/VERSION`.

Personalizza overlay in `SORGENTI/overlay/`, pacchetti in `SORGENTI/packages/extra.list.chroot`, hook in `SORGENTI/hooks/`.

---

<a id="english"></a>
## English

### What is Quelo Doctor

**Quelo Doctor** is a **live** rescue ISO for technicians and power users: broken boot, deleted files, malware checks, password recovery, Windows/Linux boot repair.

No desktop, no web browser: a fast **text menu** on the Linux console, named after the **Quelo** character by Corrado Guzzanti (see menu **C** for credits).

### Why we built it this way

| Choice | Reason |
|--------|--------|
| **Text menu, no GUI** | Works on difficult hardware; lower RAM use; predictable boot |
| **Debian sid + live-build** | Solid base, current packages, standard live ISO tooling |
| **One guided tool per menu item** | No guessing which app to run (TestDisk, mc, ClamAV…) |
| **USB automount under /media** | External drives ready for reports and logs |
| **`man`-style docs** | Credits, licenses, manual (C/M) via `man-db` + `groff` + `less` |
| **Uniform Q key** | Back/exit everywhere, consistent with standard Linux pagers |
| **amd64 only** | Matches real-world hardware; leaner build |

### Main menu

See Italian section above — same layout. Menu **L** switches locale (Italian/English).

### Rebuild your own

```bash
git clone https://github.com/alby-quelo/quelo-doctor.git
cd quelo-doctor/SORGENTI
sudo ./build.sh
```

Edit `SORGENTI/overlay/` for scripts and config, `packages/extra.list.chroot` for packages.

---

<a id="build"></a>
## Struttura repository / Repository layout

```
quelo-doctor/
├── README.md           ← questa pagina
├── docs/               ← sito GitHub Pages
├── images/             ← screenshot e mascotte
├── SORGENTI/           ← sorgenti build (overlay, hooks, build.sh)
└── ISO/                ← (solo locale) — su GitHub usa Releases
```

---

<a id="segnalare-problemi"></a>
## Segnalare problemi / Report issues

Hai trovato un bug? Apri una **[Issue](https://github.com/alby-quelo/quelo-doctor/issues/new/choose)** con:

- versione ISO (es. 0.75)  
- passi per riprodurre  
- hardware (UEFI/BIOS, dischi)  
- comportamento atteso vs osservato  

Found a bug? Open an **[Issue](https://github.com/alby-quelo/quelo-doctor/issues/new/choose)** with the same details.

---

## Licenze / Licenses

- **Quelo Doctor** (menu, script, overlay): [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/) — vedi `SORGENTI/overlay/.../licenses.*.txt`  
- **Software di terze parti**: GPL, Apache, ecc. — elenco completo in ISO menu **C** → Licenze  

---

<p align="center">
  <sub>Quelo Doctor — alpha · Ultima verificata / Last verified: <strong>0.75</strong></sub>
</p>
