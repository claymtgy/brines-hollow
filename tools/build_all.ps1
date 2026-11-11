<#
.SYNOPSIS
    Builds Brine's Hollow for Windows, Linux, and Dedicated Server.

.DESCRIPTION
    Automates building the game client and dedicated server binaries using Godot 4.
    Supports Windows Desktop, Linux Desktop, Linux Dedicated Server, and Windows Dedicated Server.

.PARAMETER Target
    The build target: "all", "windows", "linux", "server", "server_win". Default: "all".

.PARAMETER Mode
    Build mode: "debug" (default) or "release".

.PARAMETER Clean
    If specified, cleans output directories before building.

.EXAMPLE
    .\tools\build_all.ps1
    .\tools\build_all.ps1 -Target windows
    .\tools\build_all.ps1 -Target server -Mode release
#>

[CmdletBinding()]
param (
    [ValidateSet("all", "windows", "linux", "server", "server_win")]
    [string]$Target = "all",

    [ValidateSet("debug", "release")]
    [string]$Mode = "debug",

    [switch]$Clean,

    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path "$PSScriptRoot\..").Path
Set-Location $ProjectRoot

# 1. Resolve Godot executable
function Find-Godot {
    param([string]$Specified)
    if ($Specified -and (Test-Path $Specified)) {
        return (Resolve-Path $Specified).Path
    }
    if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) {
        return (Resolve-Path $env:GODOT_BIN).Path
    }
    $DefaultDesktop = "C:\Users\claym\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe"
    if (Test-Path $DefaultDesktop) {
        return $DefaultDesktop
    }
    $InPath = Get-Command godot -ErrorAction SilentlyContinue
    if ($InPath) {
        return $InPath.Source
    }
    # Check desktop / downloads for Godot 4
    $Candidates = Get-ChildItem -Path "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Downloads" -Filter "*Godot*4*.exe" -ErrorAction SilentlyContinue
    if ($Candidates -and $Candidates.Count -gt 0) {
        return $Candidates[0].FullName
    }
    return $null
}

$Godot = Find-Godot $GodotPath
if (-not $Godot) {
    Write-Error "Could not find Godot executable! Please specify -GodotPath <path_to_godot.exe> or set GODOT_BIN environment variable."
    exit 1
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Brine's Hollow Build Pipeline" -ForegroundColor Cyan
Write-Host " Engine  : $Godot" -ForegroundColor Gray
Write-Host " Target  : $Target" -ForegroundColor Gray
Write-Host " Mode    : $Mode" -ForegroundColor Gray
Write-Host "==================================================" -ForegroundColor Cyan

# 2. Setup build configurations
$ExportFlag = if ($Mode -eq "release") { "--export-release" } else { "--export-debug" }

$Configs = @{
    "windows" = @{
        Name   = "Windows Desktop"
        Preset = "Windows Desktop"
        Dir    = "$ProjectRoot\builds\windows"
        File   = "BrinesHollow.exe"
        ReqSo  = $false
    }
    "linux" = @{
        Name   = "Linux Desktop"
        Preset = "Linux Desktop"
        Dir    = "$ProjectRoot\builds\linux"
        File   = "BrinesHollow.x86_64"
        ReqSo  = $true
    }
    "server" = @{
        Name   = "Linux Dedicated Server"
        Preset = "Dedicated Server"
        Dir    = "$ProjectRoot\builds\server"
        File   = "BrinesHollowServer.x86_64"
        ReqSo  = $true
    }
    "server_win" = @{
        Name   = "Windows Dedicated Server"
        Preset = "Windows Dedicated Server"
        Dir    = "$ProjectRoot\builds\server_windows"
        File   = "BrinesHollowServer.exe"
        ReqSo  = $false
    }
}

$TargetsToBuild = if ($Target -eq "all") {
    @("windows", "linux", "server", "server_win")
} else {
    @($Target)
}

if ($Clean) {
    Write-Host "`nCleaning builds directory..." -ForegroundColor Yellow
    if (Test-Path "$ProjectRoot\builds") {
        Remove-Item -Path "$ProjectRoot\builds\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$Results = @{}

foreach ($t in $TargetsToBuild) {
    $cfg = $Configs[$t]
    $name = $cfg.Name
    $preset = $cfg.Preset
    $dir = $cfg.Dir
    $file = $cfg.File
    $outPath = "$dir\$file"

    Write-Host "`n>>> Building: $name ($preset) -> $file" -ForegroundColor Green

    # Ensure target directory exists
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    # Check for Linux GDExtension library when exporting on Windows
    $LinuxSoDebug = "$ProjectRoot\bin\libbrines.linux.template_debug.x86_64.so"
    $LinuxSoRelease = "$ProjectRoot\bin\libbrines.linux.template_release.x86_64.so"
    $HasLinuxSo = (Test-Path $LinuxSoDebug) -or (Test-Path $LinuxSoRelease)

    if ($cfg.ReqSo -and -not $HasLinuxSo) {
        Write-Host "  [NOTICE] Linux GDExtension library (.so) not found in bin/." -ForegroundColor Yellow
        Write-Host "           Exporting data pack (.pck) for Linux target." -ForegroundColor Yellow
        Write-Host "           (Run native/build.sh on Linux or WSL to compile the .so library)." -ForegroundColor Gray

        $pckPath = [System.IO.Path]::ChangeExtension($outPath, ".pck")
        $proc = Start-Process -FilePath $Godot -ArgumentList "--headless", "--path", "`"$ProjectRoot`"", "--export-pack", "`"$preset`"", "`"$pckPath`"" -Wait -NoNewWindow -PassThru

        if ($proc.ExitCode -eq 0) {
            $Results[$name] = @{ Success = $true; Path = $pckPath; Note = "PCK pack exported" }
            Write-Host "  [PASS] $name pack created at $pckPath" -ForegroundColor Green
        } else {
            $Results[$name] = @{ Success = $false; Path = $pckPath; Note = "Export pack failed with code $($proc.ExitCode)" }
            Write-Host "  [FAIL] $name export failed!" -ForegroundColor Red
        }
        continue
    }

    # Standard export
    $proc = Start-Process -FilePath $Godot -ArgumentList "--headless", "--path", "`"$ProjectRoot`"", $ExportFlag, "`"$preset`"", "`"$outPath`"" -Wait -NoNewWindow -PassThru

    if ($proc.ExitCode -eq 0 -and (Test-Path $outPath)) {
        $sizeMb = [math]::Round(((Get-Item $outPath).Length / 1MB), 2)
        $Results[$name] = @{ Success = $true; Path = $outPath; Note = "$sizeMb MB" }
        Write-Host "  [PASS] $name created ($sizeMb MB)" -ForegroundColor Green
    } else {
        $Results[$name] = @{ Success = $false; Path = $outPath; Note = "Failed with exit code $($proc.ExitCode)" }
        Write-Host "  [FAIL] $name failed!" -ForegroundColor Red
    }
}

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host " Build Summary" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

$SuccessCount = 0
foreach ($name in $Results.Keys) {
    $r = $Results[$name]
    if ($r.Success) {
        $SuccessCount++
        Write-Host "  [OK]   $name : $($r.Path) ($($r.Note))" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $name : $($r.Note)" -ForegroundColor Red
    }
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Completed $SuccessCount / $($Results.Count) targets successfully." -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

if ($SuccessCount -ne $Results.Count) {
    exit 1
}
