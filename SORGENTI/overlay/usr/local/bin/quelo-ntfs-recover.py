#!/usr/bin/env python3
"""Recupero file NTFS cancellati (whitelist) con ntfsundelete."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys


def emit_progress(pct: int, done: int, total: int, msg: str) -> None:
    print(f"PROGRESS:{pct}:{done}:{total}:{msg}", flush=True)


def emit_summary(files: int, folders: int, total_bytes: int) -> None:
    print(f"SUMMARY:{files}:{folders}:{total_bytes}", flush=True)


WHITELIST = {
    "jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif", "heic",
    "mp4", "mkv", "avi", "mov", "wmv", "mpeg", "mpg", "webm", "mts",
    "mp3", "flac", "wav", "ogg", "m4a", "aac", "wma",
    "txt", "md", "rtf",
    "pdf", "doc", "docx", "odt",
    "xls", "xlsx", "ods", "csv",
    "ppt", "pptx", "odp",
    "db", "sqlite", "sqlite3", "db3", "mdb", "accdb", "mdf", "ldf", "ndf",
    "dbf", "fdb", "nsf", "odb", "sql", "dump", "backup", "fmp12", "fp7", "fmp", "realm",
    "zip", "7z", "rar",
    "p7m", "p7s",
}


def allowed_name(name: str) -> bool:
    low = name.lower()
    if low.endswith(".h2.db"):
        return True
    if low.endswith(".p7m") or low.endswith(".p7s"):
        return True
    if "." not in low:
        return False
    return low.rsplit(".", 1)[-1] in WHITELIST


def safe_folder(name: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]", "_", name.strip())
    return cleaned or "_vari"


def scan_deleted(device: str) -> list[dict]:
    try:
        proc = subprocess.run(
            ["ntfsundelete", "--scan", device],
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        print("ERROR:ntfsundelete not found", flush=True)
        sys.exit(2)

    entries: list[dict] = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line or line.lower().startswith("inode"):
            continue
        m = re.match(
            r"^\s*(\d+)\s+(\d+)%\s+(\d+)\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+(.+)$",
            line,
        )
        if not m:
            m2 = re.match(r"^\s*(\d+)\s+.*?\s+(\d+)\s+.*?\s+(.+)$", line)
            if not m2:
                continue
            inode, size, name = m2.group(1), int(m2.group(2)), m2.group(3).strip()
        else:
            inode, size, name = m.group(1), int(m.group(3)), m.group(5).strip()
        if not allowed_name(name):
            continue
        entries.append({"inode": inode, "size": size, "name": name})
    return entries


def parent_folder_name(device: str, inode: str) -> str:
    try:
        proc = subprocess.run(
            ["ntfsinfo", "-i", inode, device],
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return "_vari"
    for line in proc.stdout.splitlines():
        line = line.strip()
        if line.lower().startswith("$filename:") or line.lower().startswith("filename:"):
            continue
        if "parent" in line.lower() and ":" in line:
            parent_inode = re.search(r":\s*(\d+)", line)
            if not parent_inode:
                continue
            pinode = parent_inode.group(1)
            proc2 = subprocess.run(
                ["ntfsinfo", "-i", pinode, device],
                capture_output=True,
                text=True,
                check=False,
            )
            for pline in proc2.stdout.splitlines():
                pline = pline.strip()
                if pline.lower().startswith("$filename:") or pline.lower().startswith("filename:"):
                    part = pline.split(":", 1)[-1].strip()
                    if part and part not in (".", "..", "/"):
                        return safe_folder(os.path.basename(part))
    return "_vari"


def undelete_one(device: str, inode: str, out_dir: str) -> bool:
    os.makedirs(out_dir, exist_ok=True)
    proc = subprocess.run(
        ["ntfsundelete", "-u", "-i", inode, "-d", out_dir, device],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.returncode == 0


def unique_dest(folder: str, name: str) -> str:
    base = os.path.join(folder, name)
    if not os.path.exists(base):
        return base
    stem, ext = os.path.splitext(name)
    n = 1
    while True:
        cand = os.path.join(folder, f"{stem}_{n}{ext}")
        if not os.path.exists(cand):
            return cand
        n += 1


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: quelo-ntfs-recover.py <device> <dest_dir>", file=sys.stderr)
        return 1

    device, dest = sys.argv[1], sys.argv[2]
    os.makedirs(dest, exist_ok=True)

    emit_progress(12, 0, 0, "scan")
    entries = scan_deleted(device)
    total = len(entries)
    if total == 0:
        emit_progress(100, 0, 0, "done")
        emit_summary(0, 0, 0)
        return 0

    emit_progress(30, 0, total, "scan")
    files_ok = 0
    folders_used: set[str] = set()
    total_bytes = 0
    staging = os.path.join(dest, ".ntfs_staging")
    if os.path.isdir(staging):
        shutil.rmtree(staging)
    os.makedirs(staging, exist_ok=True)

    for i, ent in enumerate(entries, start=1):
        pct = 30 + int(65 * i / total)
        emit_progress(pct, i, total, ent["name"][:40])
        folder = parent_folder_name(device, ent["inode"])
        folders_used.add(folder)
        target_dir = os.path.join(dest, folder)
        os.makedirs(target_dir, exist_ok=True)
        work = os.path.join(staging, ent["inode"])
        os.makedirs(work, exist_ok=True)
        if not undelete_one(device, ent["inode"], work):
            continue
        recovered = None
        for root, _dirs, files in os.walk(work):
            for fn in files:
                if fn.lower() == ent["name"].lower() or allowed_name(fn):
                    recovered = os.path.join(root, fn)
                    break
            if recovered:
                break
        if not recovered:
            continue
        final_path = unique_dest(target_dir, ent["name"])
        shutil.move(recovered, final_path)
        files_ok += 1
        try:
            total_bytes += os.path.getsize(final_path)
        except OSError:
            pass

    shutil.rmtree(staging, ignore_errors=True)
    emit_progress(100, total, total, "done")
    emit_summary(files_ok, len(folders_used) if folders_used else (1 if files_ok else 0), total_bytes)
    return 0


if __name__ == "__main__":
    sys.exit(main())
