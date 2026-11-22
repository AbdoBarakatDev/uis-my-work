# UIS My Work - one-time setup for LIVE UPDATES (Windows, Chrome and Edge).
#
# This file is made by the UIS My Work extension (Turn on live updates ->
# Download installer). Run it once: right-click -> Run with PowerShell.
#
#  1. Puts the extension in %LOCALAPPDATA%\UIS\MyWork\extension
#  2. Installs the small updater (included below) in %LOCALAPPDATA%\UIS\MyWork\updater
#     and registers it for this Windows user only (HKCU - no admin rights), so ONLY
#     the UIS My Work extension can ask it to fetch a new version from
#     https://uis-mobile-portal.web.app
#  3. Copies the extension folder path, so you can paste it into "Load unpacked".
param([switch]$Uninstall = $true)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Name  = 'com.uis.mywork.updater'
$ExtId = 'kpceidgdgjodcjcolmddjcndjbmbahpd'
$Root  = Join-Path $env:LOCALAPPDATA 'UIS\MyWork'
$Upd   = Join-Path $Root 'updater'
$Ext   = Join-Path $Root 'extension'
$Keys  = @("HKCU:\Software\Google\Chrome\NativeMessagingHosts\$Name", "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\$Name")

# The updater itself (saved as updater\host.ps1).
$HostScript = @'
# UIS My Work - live updater (Chrome / Edge native messaging host).
#
# Installed by setup.ps1 into %LOCALAPPDATA%\UIS\MyWork\updater. Chrome starts it
# (through host.bat) only for the UIS My Work extension, sends ONE message and
# reads ONE answer:
#   { "cmd": "ping" }    -> { ok, host, version, token, dir }
#   { "cmd": "update" }  -> downloads the latest release from the fixed UIS address
#                           below into %LOCALAPPDATA%\UIS\MyWork\extension
#                           -> { ok, version, changed }
# It never downloads from anywhere else and never runs what it downloads.
param([string]$Mode = '')

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$HostVersion = '1'
$Base = 'https://uis-mobile-portal.web.app'
$Root = Split-Path -Parent $PSScriptRoot
$Ext = Join-Path $Root 'extension'
if (-not $Ext.TrimEnd('\').EndsWith('UIS\MyWork\extension')) { throw "Unexpected install folder: $Ext" }

function Read-Message {
  $in = [Console]::OpenStandardInput()
  $lb = New-Object byte[] 4; $n = 0
  while ($n -lt 4) { $r = $in.Read($lb, $n, 4 - $n); if ($r -le 0) { return $null }; $n += $r }
  $len = [BitConverter]::ToInt32($lb, 0)
  if ($len -le 0 -or $len -gt 65536) { return $null }
  $buf = New-Object byte[] $len; $n = 0
  while ($n -lt $len) { $r = $in.Read($buf, $n, $len - $n); if ($r -le 0) { break }; $n += $r }
  return ([Text.Encoding]::UTF8.GetString($buf, 0, $n) | ConvertFrom-Json)
}
function Write-Message($obj) {
  $json = $obj | ConvertTo-Json -Compress -Depth 5
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $out = [Console]::OpenStandardOutput()
  $out.Write([BitConverter]::GetBytes([int]$bytes.Length), 0, 4)
  $out.Write($bytes, 0, $bytes.Length)
  $out.Flush()
}
function Get-Token {
  $f = Join-Path $PSScriptRoot 'token.txt'
  if (Test-Path $f) { return ([IO.File]::ReadAllText($f)).Trim() }
  return ''
}
# marks this folder as the updater's copy (the extension compares the token)
function Write-Managed {
  $t = Get-Token
  if ($t) { [IO.File]::WriteAllText((Join-Path $Ext 'uis-managed.json'), ('{"token":"' + $t + '"}'), (New-Object Text.UTF8Encoding $false)) }
}
function Get-InstalledVersion {
  $m = Join-Path $Ext 'manifest.json'
  if (Test-Path $m) { return [string](([IO.File]::ReadAllText($m)) | ConvertFrom-Json).version }
  return ''
}
function Compare-Version([string]$a, [string]$b) {
  $pa = @($a.Split('.') | ForEach-Object { [int]$_ }); $pb = @($b.Split('.') | ForEach-Object { [int]$_ })
  for ($i = 0; $i -lt 4; $i++) {
    $x = 0; $y = 0
    if ($i -lt $pa.Count) { $x = $pa[$i] }
    if ($i -lt $pb.Count) { $y = $pb[$i] }
    if ($x -gt $y) { return 1 }
    if ($x -lt $y) { return -1 }
  }
  return 0
}
# downloads try 3 times: networks drop a connection now and then
function Invoke-WithRetry([scriptblock]$Action) {
  for ($i = 1; $i -le 3; $i++) {
    try { return (& $Action) } catch { if ($i -eq 3) { throw }; Start-Sleep -Seconds 2 }
  }
}
function Invoke-Update {
  $info = Invoke-WithRetry { Invoke-RestMethod -Uri ("$Base/version.json?_=" + [DateTime]::UtcNow.Ticks) -UseBasicParsing -Headers @{ 'Cache-Control' = 'no-cache' } }
  $url = [string]$info.url
  if (-not $url.StartsWith("$Base/")) { throw "Refusing to download from $url" }
  $cur = Get-InstalledVersion
  if ($cur -and (Compare-Version $cur ([string]$info.version)) -ge 0) {
    Write-Managed
    return @{ ok = $true; version = $cur; changed = $false }
  }
  $tmp = Join-Path $env:TEMP ('uis-mywork-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  try {
    $zip = Join-Path $tmp 'update.zip'
    Invoke-WithRetry { Invoke-WebRequest -Uri ($url + '?_=' + [DateTime]::UtcNow.Ticks) -OutFile $zip -UseBasicParsing }
    if ($info.sha256) {
      $h = (Get-FileHash -Path $zip -Algorithm SHA256).Hash
      if ($h -ne ([string]$info.sha256).ToUpper()) { throw 'The download is damaged (checksum mismatch). Try again later.' }
    }
    $x = Join-Path $tmp 'x'
    Expand-Archive -Path $zip -DestinationPath $x -Force
    $mf = Join-Path $x 'manifest.json'
    if (-not (Test-Path $mf)) { throw 'The download has no manifest.json' }
    $nv = [string](([IO.File]::ReadAllText($mf)) | ConvertFrom-Json).version
    New-Item -ItemType Directory -Force -Path $Ext | Out-Null
    # copy the new files over the old ones, then drop files the new version no longer has
    Copy-Item -Path (Join-Path $x '*') -Destination $Ext -Recurse -Force
    $keep = @{}
    Get-ChildItem -LiteralPath $x -Recurse -Force -Name | ForEach-Object { $keep[$_.ToLower()] = $true }
    Get-ChildItem -LiteralPath $Ext -Recurse -Force -Name | Sort-Object { $_.Length } -Descending | ForEach-Object {
      if (-not $keep.ContainsKey($_.ToLower()) -and $_ -ne 'uis-managed.json') { Remove-Item -LiteralPath (Join-Path $Ext $_) -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Managed
    return @{ ok = $true; version = $nv; changed = $true }
  } finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if ($Mode -eq 'install') {
  # used by setup.ps1: put the latest version in place now
  $res = Invoke-Update
  Write-Host ("UIS My Work v" + $res.version + " is in " + $Ext)
  exit 0
}

try {
  $msg = Read-Message
  if ($null -eq $msg) { exit 0 }
  switch ([string]$msg.cmd) {
    'ping'   { Write-Message @{ ok = $true; host = $HostVersion; version = (Get-InstalledVersion); token = (Get-Token); dir = $Ext } }
    'update' { Write-Message (Invoke-Update) }
    default  { Write-Message @{ ok = $false; error = 'unknown command' } }
  }
} catch {
  try { Write-Message @{ ok = $false; error = $_.Exception.Message } } catch {}
}

'@

function Close-Window([string]$Message, [string]$Color) {
  Write-Host ''
  Write-Host $Message -ForegroundColor $Color
  Write-Host ''
  [void](Read-Host 'Press Enter to close')
}

try {
  if ($Uninstall) {
    foreach ($k in $Keys) { Remove-Item -Path $k -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $Upd -Recurse -Force -ErrorAction SilentlyContinue
    Close-Window 'Live updates are off: the UIS My Work updater was removed. The extension folder was kept.' 'Green'
    return
  }

  Write-Host ''
  Write-Host '  UIS My Work - turning on live updates' -ForegroundColor Cyan
  Write-Host ''

  # An old "auto-update" setting (uis-auto-update-setup.reg, merged as admin) makes Chrome
  # and Edge force-install the old 4.5.1 copy instead of the folder you load. Remove it.
  $Policy = @('HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist', 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist')
  $stale = @()
  foreach ($p in $Policy) {
    if (Test-Path $p) {
      $props = Get-ItemProperty -Path $p
      foreach ($n in $props.PSObject.Properties.Name) { if ("$($props.$n)" -like "$ExtId*") { $stale += ,@($p, $n) } }
    }
  }
  if ($stale.Count) {
    Write-Host '  - removing an old setting that keeps version 4.5.1 (Windows asks for permission once)' -ForegroundColor Yellow
    $cmd = ($stale | ForEach-Object { "Remove-ItemProperty -LiteralPath '$($_[0])' -Name '$($_[1])' -Force -ErrorAction SilentlyContinue" }) -join '; '
    try { Start-Process powershell.exe -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', $cmd }
    catch { Write-Host '    Permission was not given. Ask IT to remove the UIS My Work entry under ExtensionInstallForcelist.' -ForegroundColor Red }
    Write-Host '    Done. Close ALL Chrome / Edge windows once after this setup.' -ForegroundColor Yellow
  }

  New-Item -ItemType Directory -Force -Path $Upd, $Ext | Out-Null

  Write-Host '  - installing the updater'
  [IO.File]::WriteAllText((Join-Path $Upd 'host.ps1'), $HostScript, (New-Object Text.UTF8Encoding $false))
  [IO.File]::WriteAllText((Join-Path $Upd 'host.bat'), "@echo off`r`npowershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"%~dp0host.ps1`"`r`n", [Text.Encoding]::ASCII)

  $tokFile = Join-Path $Upd 'token.txt'
  if (-not (Test-Path $tokFile)) { [IO.File]::WriteAllText($tokFile, [guid]::NewGuid().ToString('N')) }

  $manifest = [ordered]@{
    name            = $Name
    description     = 'UIS My Work live updater'
    path            = (Join-Path $Upd 'host.bat')
    type            = 'stdio'
    allowed_origins = @("chrome-extension://$ExtId/")
  } | ConvertTo-Json
  $mPath = Join-Path $Upd "$Name.json"
  [IO.File]::WriteAllText($mPath, $manifest, (New-Object Text.UTF8Encoding $false))

  Write-Host '  - registering it for Chrome and Edge (this Windows user only)'
  foreach ($k in $Keys) { New-Item -Path $k -Force | Out-Null; Set-Item -Path $k -Value $mPath }

  Write-Host '  - downloading the latest UIS My Work'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Upd 'host.ps1') -Mode install
  if ($LASTEXITCODE -ne 0) { throw 'Could not download the extension. Check your internet connection and run this again.' }

  try { Set-Clipboard -Value $Ext } catch {}
  Write-Host ''
  Write-Host '  Done. One last step (only once):' -ForegroundColor Green
  Write-Host '   1. Open chrome://extensions  (Edge: edge://extensions)'
  Write-Host '   2. Remove "UIS Portal - My Work Tracker" if it is there'
  Write-Host '   3. Turn on Developer mode, click "Load unpacked" and paste this folder'
  Write-Host '      (it is already copied - just press Ctrl+V in the folder box):'
  Write-Host ''
  Write-Host "      $Ext" -ForegroundColor Yellow
  Close-Window '  From then on, new versions install by themselves.' 'Green'
} catch {
  Close-Window ('Setup failed: ' + $_.Exception.Message) 'Red'
}
