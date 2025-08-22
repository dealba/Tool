<# 
 H4N53N Tool - Console edition (winget + tweaks)
 - Works in PowerShell 5.1 and 7.x
 - No WPF, no Unicode punctuation (safe encoding)
 - Uses profiles\apps-*.json and tweaks.ps1 in same folder
#>

param(
  [switch]$DryRun,
  [switch]$Silent = $true
)

$ErrorActionPreference = 'Stop'
$ToolName   = 'H4N53N Tool'
$Root       = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$LogDir     = Join-Path $env:ProgramData 'H4N53N-Tool\Logs'
$LogFile    = Join-Path $LogDir ("install_{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))

# ---------- Logging ----------
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
function Write-Log {
  param([string]$Message, [string]$Level = 'INFO')
  $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message
  Write-Host $line
  Add-Content -LiteralPath $LogFile -Value $line
}

# ---------- Admin elevation ----------
function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = [Security.Principal.WindowsPrincipal]$id
  return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
if (-not (Test-IsAdmin)) {
  Write-Host "Restarting $ToolName as Administrator..."
  $argList = @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`"")
  if ($DryRun) { $argList += "-DryRun" }
  if ($Silent) { $argList += "-Silent" }
  Start-Process -FilePath "powershell" -ArgumentList $argList -Verb RunAs | Out-Null
  exit
}

Write-Log "Start. DryRun=$DryRun Silent=$Silent"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Log "winget not found. Install 'App Installer' from Microsoft Store." "ERROR"
  throw "winget missing"
}

# ---------- Load profiles ----------
$profiles = @('essentials','dev','gaming')  # extend as needed
$apps = New-Object System.Collections.Generic.List[object]

foreach ($p in $profiles) {
  $path = Join-Path $Root ("profiles\apps-{0}.json" -f $p)
  if (Test-Path $path) {
    try {
      $json = Get-Content $path -Raw | ConvertFrom-Json
      foreach ($a in $json) {
        $apps.Add([pscustomobject]@{
          Profile = $p
          Name    = $a.name
          Id      = $a.id
          Source  = if ($a.PSObject.Properties.Name -contains 'source' -and $a.source) { $a.source } else { 'winget' }
        })
      }
    } catch {
      Write-Log "Failed to parse $path : $($_.Exception.Message)" "ERROR"
    }
  } else {
    Write-Log "Profile file missing: $path" "WARN"
  }
}

# Deduplicate by Id
$apps = $apps | Sort-Object Id -Unique
if ($apps.Count -eq 0) {
  Write-Log "No apps found in profiles folder." "ERROR"
  throw "No apps"
}

# ---------- Choose profiles ----------
Write-Host ""
Write-Host "Available profiles:"
for ($i=0; $i -lt $profiles.Count; $i++) {
  Write-Host ("  [{0}] {1}" -f ($i+1), $profiles[$i])
}
$profSel = Read-Host "Select profiles by number (comma separated) or 'all' (ENTER = all)"
if ([string]::IsNullOrWhiteSpace($profSel) -or $profSel -eq 'all') {
  $chosenProfiles = $profiles
} else {
  $idxs = $profSel -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
  $chosenProfiles = foreach ($j in $idxs) { if ($j -ge 1 -and $j -le $profiles.Count) { $profiles[$j-1] } }
  if (-not $chosenProfiles -or $chosenProfiles.Count -eq 0) { $chosenProfiles = $profiles }
}

# Filter apps by chosen profiles
$appsFiltered = $apps | Where-Object { $chosenProfiles -contains $_.Profile }

# ---------- Choose apps ----------
Write-Host ""
Write-Host "Apps in selected profiles:"
for ($i=0; $i -lt $appsFiltered.Count; $i++) {
  $a = $appsFiltered[$i]
  Write-Host ("  [{0}] {1}  ({2})  [{3}]" -f ($i+1), $a.Name, $a.Id, $a.Profile)
}
$appSel = Read-Host "Select apps by number (comma separated) or 'all' (ENTER = all)"
if ([string]::IsNullOrWhiteSpace($appSel) -or $appSel -eq 'all') {
  $chosenApps = $appsFiltered
} else {
  $idxs = $appSel -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
  $chosenApps = foreach ($j in $idxs) { if ($j -ge 1 -and $j -le $appsFiltered.Count) { $appsFiltered[$j-1] } }
}

if (-not $chosenApps -or $chosenApps.Count -eq 0) {
  Write-Log "No apps selected. Exiting."
  return
}

# ---------- Tweaks ----------
$tweaksCatalog = @(
  @{ Key='DisableBingInSearch';   Label='Disable Bing in Start/Search' },
  @{ Key='ShowFileExtensions';    Label='Show file extensions in Explorer' },
  @{ Key='TaskbarSmallIcons';     Label='Small taskbar icons' },
  @{ Key='DisableTelemetryBasic'; Label='Reduce basic telemetry' }
)

Write-Host ""
Write-Host "Tweaks:"
for ($i=0; $i -lt $tweaksCatalog.Count; $i++) {
  Write-Host ("  [{0}] {1}" -f ($i+1), $tweaksCatalog[$i].Label)
}
$tweakSel = Read-Host "Select tweaks (comma separated), or ENTER for none"
$chosenTweaks = @()
if (-not [string]::IsNullOrWhiteSpace($tweakSel)) {
  $idxs = $tweakSel -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
  foreach ($j in $idxs) {
    if ($j -ge 1 -and $j -le $tweaksCatalog.Count) {
      $chosenTweaks += $tweaksCatalog[$j-1].Key
    }
  }
}

# ---------- Run tweaks ----------
if ($chosenTweaks.Count -gt 0) {
  $tw = Join-Path $Root 'tweaks.ps1'
  if (Test-Path $tw) {
    if ($DryRun) {
      Write-Log ("[DRY-RUN] Would run tweaks: {0}" -f ($chosenTweaks -join ', '))
    } else {
      Write-Log ("Running tweaks: {0}" -f ($chosenTweaks -join ', '))
      & powershell -NoProfile -ExecutionPolicy Bypass -File $tw -Tweaks $chosenTweaks -DryRun:$DryRun
    }
  } else {
    Write-Log "tweaks.ps1 not found next to install.ps1" "WARN"
  }
}

# ---------- Install apps ----------
function Invoke-WingetInstall {
  param([string]$Id)
  $args = @(
    'install','--exact','--id', $Id,
    '--accept-package-agreements','--accept-source-agreements'
  )
  if ($Silent) { $args += '--silent' }
  # valgfrit: undgå popups
  $args += '--disable-interactivity'

  $argLine = ($args -join ' ')
  Write-Log ("CMD: winget " + $argLine)

  if ($DryRun) { return 0 }

  try {
    $p = Start-Process -FilePath 'winget' -ArgumentList $args -NoNewWindow -Wait -PassThru
    return [int]$p.ExitCode
  } catch {
    Write-Log ("winget failed for {0}: {1}" -f $Id, $_.Exception.Message) "ERROR"
    return 1
  }
}

Write-Host ""
Write-Log ("Installing {0} app(s)..." -f $chosenApps.Count)
foreach ($app in $chosenApps) {
  if ($app.Source -ne 'winget') {
    Write-Log ("Unknown source '{0}' for {1} - skipping." -f $app.Source, $app.Name) "WARN"
    continue
  }
  Write-Log ("Installing: {0} ({1})" -f $app.Name, $app.Id)
  $code = Invoke-WingetInstall -Id $app.Id
  if ($code -eq 0) {
    Write-Log ("OK: {0} installed." -f $app.Name)
  } else {
    Write-Log ("ERROR: {0} failed with code {1}." -f $app.Name, $code) "ERROR"
  }
}

Write-Log "Done."
Write-Host ""
Write-Host ("Log file: {0}" -f $LogFile)