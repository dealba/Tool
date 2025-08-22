param(
  [string[]]$Tweaks,
  [switch]$DryRun
)


function Do {
  param([string]$Desc, [scriptblock]$Action)
  if ($DryRun) { Write-Host "[DRY-RUN] $Desc"; return }
  Write-Host $Desc
  & $Action
}

foreach ($t in $Tweaks) {
  switch ($t) {
    'DisableBingInSearch' {
      Do "Slår Bing/Web i Windows-søgning fra" { 
        New-Item -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Force | Out-Null
        Set-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\Explorer" DisableSearchBoxSuggestions 1 -Type DWord
      }
    }
    'ShowFileExtensions' {
      Do "Vis filendelser i Explorer" {
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" HideFileExt 0 -Type DWord
      }
    }
    'TaskbarSmallIcons' {
      Do "Aktiver små ikoner på taskbar" {
        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" TaskbarSmallIcons 1 -Type DWord
        Stop-Process -Name explorer -Force
      }
    }
    'DisableTelemetryBasic' {
      Do "Reducer grundlæggende telemetri" {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" AllowTelemetry 0 -Type DWord
      }
    }
    default {
      Write-Host "Ukendt tweak: $t"
    }
  }
}
