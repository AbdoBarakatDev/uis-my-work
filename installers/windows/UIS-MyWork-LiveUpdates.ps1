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
param([switch]$Uninstall)

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
# Host 2: an update is installed only when its zip carries a valid RSA signature
# ("sig" in version.json: RSA PKCS#1 v1.5 + SHA-256 over the exact zip bytes) made
# with the UIS release key, whose public half is embedded below by
# tools/embed-updater.js. The new version is unpacked next to the live folder and
# swapped in, so a failed update never leaves a half-copied extension behind.
param([string]$Mode = '')

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$HostVersion = '2'
$Base = 'https://uis-mobile-portal.web.app'
# Release public key (RSA modulus / exponent, base64). Filled in by tools/embed-updater.js.
$PubN = 'pFNGMapuzwiXmHEKB9JimLONYF5eyvq/rVzcZt56gV07FUZhgZm5JjaVoGA4WXsHA/59Knd7Z0DW/9xtMtyn7bOKIRwdpj5HQW+s0ViVZLYmS7xwMMD8ly14q/6qwI9rnQccBJtSajQMewYIcoaxqOBwU6HOzHf1n6dVONHe3wixqItT/WluckY45ZbQCxmeMogC3UHAd4HEJlLvyrGlBBxMqfy1qWxO5Qpple00gaFqakM0rOfaxafv8OLX62ZINIi2+QoR3cmT7geWxS4JVnl4dXFm1Zz6bTYc+tb4Ma3vmfS6OB3lB1Ibwa2r2I8At4Xbw3z32wSqtxkCobi5w1FyjzbKgvI2/+xzLJFzdsCAsqVWSTT9fHHbAEanFaXG8HyfuvFf6onFzJcjfMPvgwVQ4yq7GDYRFDxT+JU1QY7mAmDXFOXjFp8ryuDRunHP1h9WVnk0piXhjw16NZLt/hvEAHf61IZ7Ni9FJwRNDtq+7Qanz++JKDw2RJ5aS/ZT'
$PubE = 'AQAB'
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
# Throws unless $SigB64 is a valid release-key signature of $Data.
function Assert-Signature([byte[]]$Data, [string]$SigB64) {
  if ($PubN -like '__UIS*') { throw 'This updater has no release key. Run the latest live-updates installer again.' }
  if (-not $SigB64) { throw 'The update is not signed. It was not installed.' }
  try { $sig = [Convert]::FromBase64String($SigB64) } catch { throw 'The update signature is unreadable. It was not installed.' }
  $p = New-Object Security.Cryptography.RSAParameters
  $p.Modulus = [Convert]::FromBase64String($PubN)
  $p.Exponent = [Convert]::FromBase64String($PubE)
  if ('System.Security.Cryptography.RSACng' -as [type]) {
    $rsa = New-Object Security.Cryptography.RSACng
    $rsa.ImportParameters($p)
    $ok = $rsa.VerifyData($Data, $sig, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
  } else {
    # older .NET: provider 24 (PROV_RSA_AES) is the one that supports SHA-256
    $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider (New-Object Security.Cryptography.CspParameters 24)
    $rsa.PersistKeyInCsp = $false
    $rsa.ImportParameters($p)
    $ok = $rsa.VerifyData($Data, 'SHA256', $sig)
  }
  if (-not $ok) { throw 'The update signature is not valid. It was not installed.' }
}
# A crash between the two renames of a swap can leave no live folder: put the old one back.
function Restore-Interrupted {
  if (Test-Path -LiteralPath $Ext) { return }
  $old = Get-ChildItem -LiteralPath $Root -Directory -Force -Filter '.old-*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($old) { Rename-Item -LiteralPath $old.FullName -NewName 'extension' }
}
# Fallback when the live folder can't be renamed (a file in it is open): copy in place,
# manifest.json LAST, so an interrupted copy still reports the old version and the
# next check repairs it.
function Copy-InPlace([string]$From) {
  Get-ChildItem -LiteralPath $From -Force | Where-Object { $_.Name -ne 'manifest.json' } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Ext -Recurse -Force
  }
  $keep = @{}
  Get-ChildItem -LiteralPath $From -Recurse -Force -Name | ForEach-Object { $keep[$_.ToLower()] = $true }
  Get-ChildItem -LiteralPath $Ext -Recurse -Force -Name | Sort-Object { $_.Length } -Descending | ForEach-Object {
    if (-not $keep.ContainsKey($_.ToLower()) -and $_ -ne 'uis-managed.json' -and $_ -ne 'manifest.json') { Remove-Item -LiteralPath (Join-Path $Ext $_) -Recurse -Force -ErrorAction SilentlyContinue }
  }
  Copy-Item -LiteralPath (Join-Path $From 'manifest.json') -Destination $Ext -Force
}
function Invoke-Update {
  Restore-Interrupted
  $info = Invoke-WithRetry { Invoke-RestMethod -Uri ("$Base/version.json?_=" + [DateTime]::UtcNow.Ticks) -UseBasicParsing -Headers @{ 'Cache-Control' = 'no-cache' } }
  $url = [string]$info.url
  $want = [string]$info.version
  if (-not $url.StartsWith("$Base/")) { throw "Refusing to download from $url" }
  if (-not $want) { throw 'The update information has no version.' }
  if (-not $info.sha256) { throw 'The update information has no checksum. It was not installed.' }
  $cur = Get-InstalledVersion
  if ($cur -and (Compare-Version $cur $want) -ge 0) {
    Write-Managed
    return @{ ok = $true; version = $cur; changed = $false }
  }
  $id = [guid]::NewGuid().ToString('N')
  $tmp = Join-Path $env:TEMP ('uis-mywork-' + $id)
  $stage = Join-Path $Root ('.staging-' + $id)   # same drive as the live folder, so the swap is a rename
  $old = Join-Path $Root ('.old-' + $id)
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  try {
    $zip = Join-Path $tmp 'update.zip'
    Invoke-WithRetry { Invoke-WebRequest -Uri ($url + '?_=' + [DateTime]::UtcNow.Ticks) -OutFile $zip -UseBasicParsing }
    $h = (Get-FileHash -Path $zip -Algorithm SHA256).Hash
    if ($h -ne ([string]$info.sha256).ToUpper()) { throw 'The download is damaged (checksum mismatch). Try again later.' }
    Assert-Signature ([IO.File]::ReadAllBytes($zip)) ([string]$info.sig)
    Expand-Archive -Path $zip -DestinationPath $stage -Force
    $mf = Join-Path $stage 'manifest.json'
    if (-not (Test-Path $mf)) { throw 'The download has no manifest.json' }
    $nv = [string](([IO.File]::ReadAllText($mf)) | ConvertFrom-Json).version
    if ($nv -ne $want) { throw "The download is v$nv, not v$want. It was not installed." }
    if ($cur -and (Compare-Version $nv $cur) -le 0) { throw "The download (v$nv) is not newer than v$cur. It was not installed." }
    $managed = Join-Path $Ext 'uis-managed.json'
    if (Test-Path -LiteralPath $managed) { Copy-Item -LiteralPath $managed -Destination $stage -Force }
    if (-not (Test-Path -LiteralPath $Ext)) {
      Rename-Item -LiteralPath $stage -NewName 'extension'
    } else {
      $moved = $false
      try { Rename-Item -LiteralPath $Ext -NewName (Split-Path -Leaf $old); $moved = $true } catch {}
      if ($moved) {
        try { Rename-Item -LiteralPath $stage -NewName 'extension' }
        catch { Rename-Item -LiteralPath $old -NewName 'extension'; throw ('Could not put the new version in place: ' + $_.Exception.Message) }
      } else {
        Copy-InPlace $stage
      }
    }
    Write-Managed
    return @{ ok = $true; version = $nv; changed = $true }
  } finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    if ((Test-Path -LiteralPath $old) -and (Test-Path -LiteralPath $Ext)) { Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue }
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
