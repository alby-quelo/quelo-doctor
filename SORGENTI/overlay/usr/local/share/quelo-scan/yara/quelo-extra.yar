/*
 * Regole Quelo Doctor — pattern PUA/adware/persistenza noti (offline).
 */
rule Quelo_Suspicious_DoubleExtension {
    meta:
        description = "Doppia estensione eseguibile sospetta"
    strings:
        $a = ".pdf.exe" nocase
        $b = ".doc.exe" nocase
        $c = ".jpg.exe" nocase
        $d = ".mp4.exe" nocase
    condition:
        any of them
}

rule Quelo_Autorun_Inf {
    meta:
        description = "Autorun.inf sospetto"
    strings:
        $s1 = "[autorun]" nocase
        $s2 = "open=" nocase
        $s3 = "shellexecute=" nocase
    condition:
        $s1 and ($s2 or $s3)
}

rule Quelo_Powershell_Download {
    meta:
        description = "PowerShell download/codifica sospetto"
    strings:
        $a = "DownloadString" nocase
        $b = "Invoke-Expression" nocase
        $c = "IEX(" nocase
        $d = "FromBase64String" nocase
    condition:
        2 of them
}
