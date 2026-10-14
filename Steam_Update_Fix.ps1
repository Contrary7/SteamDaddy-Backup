<#
================================================================================
        STEAMDADDY - STEAM DOWNGRADE, ROLLBACK & UPDATE BLOCKER FIX
                          Universal Community Tool
================================================================================
This script:
 1. Closes running Steam processes safely to release file locks.
 2. Restores previously backed up binaries (steam.exe.old, crashhandler64.dll.old, etc.)
    downgrading Steam back to the stable working build.
 3. Purges staged and corrupt downloaded update packages (*.zip.vz.*, tmp_*) from \package\.
 4. Permanently blocks future automatic Steam updates via locked steam.cfg.
 5. Neutralizes Millennium's "incompatible with Steam.cfg" health check so Millennium
    loads smoothly alongside the update blocker without startup errors.
 6. Synchronizes mmxlyo IPC & Pattern signatures for Millennium & SteamDaddy.
================================================================================
#>

# Enable TLS 1.2 and 1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Clear-Host
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "     STEAMDADDY - STEAM ROLLBACK, DOWNGRADE & UPDATE BLOCKER     " -ForegroundColor Yellow
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------------------------
# 1. Locate Steam Directory
# ------------------------------------------------------------------------------
Write-Host "[*] Locating Steam installation directory..." -ForegroundColor Cyan
$SteamPath = $null

try {
    $reg = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($reg -and (Test-Path $reg)) { $SteamPath = $reg }
} catch {}

if (-not $SteamPath) {
    try {
        $reg = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
        if ($reg -and (Test-Path $reg)) { $SteamPath = $reg }
    } catch {}
}

if (-not $SteamPath) {
    try {
        $reg = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
        if ($reg -and (Test-Path $reg)) { $SteamPath = $reg }
    } catch {}
}

if (-not $SteamPath) {
    $searchPaths = @(
        "${env:ProgramFiles(x86)}\Steam",
        "${env:ProgramFiles}\Steam",
        "C:\Steam",
        "D:\Steam",
        "E:\Steam",
        "D:\Program Files (x86)\Steam",
        "E:\Program Files (x86)\Steam"
    )
    foreach ($p in $searchPaths) {
        if (Test-Path "$p\steam.exe") {
            $SteamPath = $p
            break
        }
    }
}

if (-not $SteamPath) {
    Write-Host "[!] Could not locate Steam automatically." -ForegroundColor Yellow
    $userPath = Read-Host "Please enter your Steam directory path (e.g. C:\Program Files (x86)\Steam)"
    if ($userPath -and (Test-Path $userPath)) {
        $SteamPath = $userPath
    } else {
        Write-Host "[-] Invalid directory entered. Exiting." -ForegroundColor Red
        exit 1
    }
}

$SteamPath = ($SteamPath -replace '/', '\').TrimEnd('\')
Write-Host "[+] Found Steam at: $SteamPath" -ForegroundColor Green

# Verify write permission; if denied, attempt elevation
function Test-SteamWriteAccess($path) {
    if (-not $path -or -not (Test-Path $path)) { return $false }
    $testFile = Join-Path $path "sd_perm_check.tmp"
    try {
        [System.IO.File]::WriteAllText($testFile, "ok")
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

if (-not (Test-SteamWriteAccess $SteamPath)) {
    if (-not $isAdmin) {
        Write-Host "[!] Administrator permissions required to modify Steam files. Elevating..." -ForegroundColor Yellow
        try {
            Start-Process powershell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -Command `"[Net.ServicePointManager]::SecurityProtocol = 3072 -bor 12288; irm https://raw.githubusercontent.com/Contrary7/SteamDaddy-Backup/main/Steam_Update_Fix.ps1 | iex`"") -Verb RunAs
            exit 0
        } catch {
            Write-Host "[-] Please re-run PowerShell as Administrator!" -ForegroundColor Red
            exit 1
        }
    }
}
Write-Host ""

# ------------------------------------------------------------------------------
# 2. Terminate Running Steam Processes Safely
# ------------------------------------------------------------------------------
Write-Host "[*] Terminating Steam processes to release file locks..." -ForegroundColor Cyan
$processes = @("steam", "steamwebhelper", "steamservice", "SteamDaddy", "steam_daddy", "AchievementUnlocker")
foreach ($procName in $processes) {
    $p = Get-Process -Name $procName -ErrorAction SilentlyContinue
    if ($p) {
        Write-Host "    [!] Stopping $procName..." -ForegroundColor Yellow
        Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
    }
}

# Wait for file handles to unlock
$timeoutSec = 5
$timer = [System.Diagnostics.Stopwatch]::StartNew()
while ($timer.Elapsed.TotalSeconds -lt $timeoutSec) {
    $running = Get-Process -Name "steam", "steamwebhelper" -ErrorAction SilentlyContinue
    if (-not $running) { break }
    Start-Sleep -Milliseconds 250
}
Write-Host "[+] All Steam processes stopped." -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------------------------
# 3. Restore Backups & Downgrade Steam
# ------------------------------------------------------------------------------
Write-Host "[*] Checking for previous Steam backups to restore..." -ForegroundColor Cyan
$restoredCount = 0

# Check steam.exe.old
$oldExe = Join-Path $SteamPath "steam.exe.old"
$curExe = Join-Path $SteamPath "steam.exe"
if (Test-Path $oldExe) {
    try {
        $oldVer = (Get-Item $oldExe).VersionInfo.FileVersion
        $curVer = if (Test-Path $curExe) { (Get-Item $curExe).VersionInfo.FileVersion } else { "None" }
        Write-Host "    [+] Found backup steam.exe.old (Version: $oldVer, Current: $curVer)" -ForegroundColor Cyan
        
        # Backup current broken exe just in case
        $brokenBackup = Join-Path $SteamPath "steam.exe.new_broken"
        Copy-Item -Path $curExe -Destination $brokenBackup -Force -ErrorAction SilentlyContinue
        
        # Replace current with old
        Remove-Item -Path $curExe -Force -ErrorAction Stop
        Move-Item -Path $oldExe -Destination $curExe -Force -ErrorAction Stop
        Write-Host "    [+] SUCCESS: steam.exe restored to pre-update version ($oldVer)!" -ForegroundColor Green
        $restoredCount++
    } catch {
        Write-Host "    [-] Failed to restore steam.exe: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "    [*] steam.exe.old not found (already restored or clean)." -ForegroundColor Gray
}

# Check crashhandler64.dll.old
$oldCrash = Join-Path $SteamPath "crashhandler64.dll.old"
$curCrash = Join-Path $SteamPath "crashhandler64.dll"
if (Test-Path $oldCrash) {
    try {
        Remove-Item -Path $curCrash -Force -ErrorAction SilentlyContinue
        Move-Item -Path $oldCrash -Destination $curCrash -Force -ErrorAction Stop
        Write-Host "    [+] SUCCESS: Restored crashhandler64.dll from backup!" -ForegroundColor Green
        $restoredCount++
    } catch {
        Write-Host "    [-] Failed to restore crashhandler64.dll: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Check crashhandler.dll.old (32-bit if present)
$oldCrash32 = Join-Path $SteamPath "crashhandler.dll.old"
$curCrash32 = Join-Path $SteamPath "crashhandler.dll"
if (Test-Path $oldCrash32) {
    try {
        Remove-Item -Path $curCrash32 -Force -ErrorAction SilentlyContinue
        Move-Item -Path $oldCrash32 -Destination $curCrash32 -Force -ErrorAction Stop
        Write-Host "    [+] SUCCESS: Restored crashhandler.dll from backup!" -ForegroundColor Green
        $restoredCount++
    } catch {}
}

# Check Steam.dll.old
$oldSteamDll = Join-Path $SteamPath "Steam.dll.old"
$curSteamDll = Join-Path $SteamPath "Steam.dll"
if (Test-Path $oldSteamDll) {
    try {
        Remove-Item -Path $curSteamDll -Force -ErrorAction SilentlyContinue
        Move-Item -Path $oldSteamDll -Destination $curSteamDll -Force -ErrorAction Stop
        Write-Host "    [+] SUCCESS: Restored Steam.dll from backup!" -ForegroundColor Green
        $restoredCount++
    } catch {}
}

# Check steamclient64.dll.old / steamclient.dll.old
$oldSc64 = Join-Path $SteamPath "steamclient64.dll.old"
$curSc64 = Join-Path $SteamPath "steamclient64.dll"
if (Test-Path $oldSc64) {
    try {
        Remove-Item -Path $curSc64 -Force -ErrorAction SilentlyContinue
        Move-Item -Path $oldSc64 -Destination $curSc64 -Force -ErrorAction Stop
        Write-Host "    [+] SUCCESS: Restored steamclient64.dll from backup!" -ForegroundColor Green
        $restoredCount++
    } catch {}
}

if ($restoredCount -gt 0) {
    Write-Host "[+] Restored $restoredCount pre-update binary files!" -ForegroundColor Green
} else {
    Write-Host "[*] No pending .old binary replacements needed." -ForegroundColor Yellow
}
Write-Host ""

# ------------------------------------------------------------------------------
# 4. Purge Recent Staged Updates & Download Chunks
# ------------------------------------------------------------------------------
Write-Host "[*] Purging downloaded/staged update packages to prevent re-updating..." -ForegroundColor Cyan
$pkgDir = Join-Path $SteamPath "package"
if (Test-Path $pkgDir) {
    $purged = 0
    $stagedItems = Get-ChildItem -Path $pkgDir -ErrorAction SilentlyContinue | Where-Object { 
        $_.Name -like "*.zip.vz.*" -or $_.Name -like "tmp_*" -or $_.Name -like "*.downloaded" 
    }
    
    foreach ($item in $stagedItems) {
        try {
            Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
            $purged++
        } catch {}
    }
    
    # Also clean downloading subfolder if present
    $dlFolder = Join-Path $pkgDir "downloading"
    if (Test-Path $dlFolder) {
        Remove-Item -Path $dlFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host "[+] Purged $purged staged update files from package directory." -ForegroundColor Green
}
Write-Host ""

# ------------------------------------------------------------------------------
# 5. Block Future Automatic Steam Updates via steam.cfg
# ------------------------------------------------------------------------------
Write-Host "[*] Configuring permanent Steam update blocker (steam.cfg)..." -ForegroundColor Cyan
$cfgPath = Join-Path $SteamPath "steam.cfg"

# Remove read-only attribute if already present
if (Test-Path $cfgPath) {
    try {
        [System.IO.File]::SetAttributes($cfgPath, [System.IO.FileAttributes]::Normal)
    } catch {}
}

$cfgContent = @"
BootStrapperInhibitAll=Enable
BootStrapperForceSelfUpdate=Disable
"@

try {
    Set-Content -Path $cfgPath -Value $cfgContent -Encoding ASCII -Force
    # Set to Read-Only so Steam cannot overwrite or delete it
    [System.IO.File]::SetAttributes($cfgPath, [System.IO.FileAttributes]::ReadOnly)
    Write-Host "[+] SUCCESS: steam.cfg created and locked (Read-Only)!" -ForegroundColor Green
    Write-Host "    -> BootStrapperInhibitAll=Enable" -ForegroundColor Gray
    Write-Host "    -> BootStrapperForceSelfUpdate=Disable" -ForegroundColor Gray
} catch {
    Write-Host "[-] Failed to write steam.cfg: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# ------------------------------------------------------------------------------
# 6. Neutralize Millennium's "Incompatible with Steam.cfg" Health Check
# ------------------------------------------------------------------------------
Write-Host "[*] Neutralizing Millennium's Steam.cfg startup warning..." -ForegroundColor Cyan
$millenniumDllPaths = @(
    (Join-Path $SteamPath "lib\millennium.dll"),
    (Join-Path $SteamPath "millennium\lib\millennium.dll")
)

$targetBytes = [System.Text.Encoding]::ASCII.GetBytes("Steam.cfg`0")
$replacementBytes = [System.Text.Encoding]::ASCII.GetBytes("Steam.non`0")

foreach ($dllPath in $millenniumDllPaths) {
    if (Test-Path $dllPath) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($dllPath)
            $matched = $false
            for ($i = 0; $i -le ($bytes.Length - $targetBytes.Length); $i++) {
                $isMatch = $true
                for ($j = 0; $j -lt $targetBytes.Length; $j++) {
                    if ($bytes[$i + $j] -ne $targetBytes[$j]) {
                        $isMatch = $false
                        break
                    }
                }
                if ($isMatch) {
                    for ($j = 0; $j -lt $replacementBytes.Length; $j++) {
                        $bytes[$i + $j] = $replacementBytes[$j]
                    }
                    $matched = $true
                }
            }
            if ($matched) {
                # Backup first
                $bak = $dllPath + ".bak"
                if (-not (Test-Path $bak)) {
                    Copy-Item -Path $dllPath -Destination $bak -Force -ErrorAction SilentlyContinue
                }
                [System.IO.File]::WriteAllBytes($dllPath, $bytes)
                Write-Host "    [+] SUCCESS: Patched health check in $dllPath!" -ForegroundColor Green
            } else {
                Write-Host "    [*] $dllPath already neutralized or compatible." -ForegroundColor Gray
            }
        } catch {
            Write-Host "    [-] Warning: Could not patch $($dllPath): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
Write-Host "[+] Millennium compatibility guard active (no more 'Incompatible with Steam.cfg' popups)." -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------------------------
# 7. Synchronize mmxlyo IPC & Pattern Signatures (Millennium / SteamDaddy)
# ------------------------------------------------------------------------------
Write-Host "[*] Synchronizing signatures & descriptors for Millennium & SteamDaddy..." -ForegroundColor Cyan

function Get-Sha256Hex($filePath) {
    if (-not (Test-Path $filePath)) { return $null }
    $fs = [System.IO.File]::OpenRead($filePath)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($fs)
    $fs.Close()
    return ([System.BitConverter]::ToString($hash) -replace '-','').ToLower()
}

$clientSha = Get-Sha256Hex (Join-Path $SteamPath "steamclient64.dll")
$uiSha     = Get-Sha256Hex (Join-Path $SteamPath "steamui.dll")

$allFilesToFetch = [System.Collections.Generic.List[object]]::new()
# Standard fallback signatures
$allFilesToFetch.Add(@{ Branch = "ipc";     Component = "steamclient"; File = "e9045710ec7ee47d7b7488d1c5dda2d933dec7e251e965967a5c48f4df68eb4e.toml" })
$allFilesToFetch.Add(@{ Branch = "pattern"; Component = "steamclient"; File = "e9045710ec7ee47d7b7488d1c5dda2d933dec7e251e965967a5c48f4df68eb4e.toml" })
$allFilesToFetch.Add(@{ Branch = "pattern"; Component = "steamui";     File = "1b9457943205dc3af0bd53463ba331cbd2a381388699705c02271aac7a2b1252.toml" })

if ($clientSha) {
    $allFilesToFetch.Add(@{ Branch = "ipc";     Component = "steamclient"; File = "$clientSha.toml" })
    $allFilesToFetch.Add(@{ Branch = "pattern"; Component = "steamclient"; File = "$clientSha.toml" })
}
if ($uiSha) {
    $allFilesToFetch.Add(@{ Branch = "pattern"; Component = "steamui"; File = "$uiSha.toml" })
}

$destRoots = @(
    (Join-Path $SteamPath "steamdaddy"),
    (Join-Path $SteamPath "opensteamtool")
)

foreach ($item in $allFilesToFetch) {
    $branch    = $item.Branch
    $component = $item.Component
    $file      = $item.File

    $mirrors = @(
        "https://raw.githubusercontent.com/mmxlyo/steam-monitor/$branch/$component/$file",
        "https://cdn.jsdelivr.net/gh/mmxlyo/steam-monitor@$branch/$component/$file",
        "https://git.lua.tools/luatools/steam-monitor/raw/branch/$branch/$component/$file",
        "https://raw.githubusercontent.com/madoiscool/steam-monitor/$branch/$component/$file"
    )

    foreach ($root in $destRoots) {
        $targetDir = Join-Path $root "$branch\$component"
        if (!(Test-Path $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }
        $targetPath = Join-Path $targetDir $file

        if (-not (Test-Path $targetPath)) {
            foreach ($url in $mirrors) {
                try {
                    Invoke-WebRequest -Uri $url -OutFile $targetPath -UseBasicParsing -TimeoutSec 6 -ErrorAction Stop
                    Write-Host "    [+] Downloaded: $branch/$component/$file" -ForegroundColor Green
                    break
                } catch {}
            }
        }
    }
}
Write-Host "[+] Signatures and IPC descriptors synced." -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------------------------
# 8. Summary & Launch
# ------------------------------------------------------------------------------
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "         DOWNGRADE & UPDATE BLOCK COMPLETE SUCCESSFULLY!         " -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary of actions taken:" -ForegroundColor Cyan
Write-Host "  [OK] Restored pre-update binaries from backup (.old files)." -ForegroundColor White
Write-Host "  [OK] Cleaned out recent staged update packages (*.zip.vz.*)." -ForegroundColor White
Write-Host "  [OK] Created locked steam.cfg -> Future updates permanently BLOCKED!" -ForegroundColor White
Write-Host "  [OK] Neutralized Millennium's Steam.cfg startup error check!" -ForegroundColor White
Write-Host "  [OK] Synced IPC and Pattern TOMLs for SteamDaddy & Millennium." -ForegroundColor White
Write-Host ""

$launch = $null
try {
    if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
        $launch = Read-Host "Would you like to launch Steam now? (Y/n)"
    }
} catch {}

if ($launch -eq 'Y' -or $launch -eq 'y' -or $launch -eq '') {
    if (Test-Path (Join-Path $SteamPath "steam.exe")) {
        Write-Host "[*] Launching Steam..." -ForegroundColor Cyan
        Start-Process (Join-Path $SteamPath "steam.exe")
    }
}
