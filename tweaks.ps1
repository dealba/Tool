param(
  [string[]]$Tweaks,
  [switch]$DryRun
)

function Invoke-TweakAction {
  param([string]$Description,[scriptblock]$Action)
  if ($DryRun) { 
    Write-Host "[DRY-RUN] $Description"
    return
  }
  Write-Host $Description
  & $Action
}

foreach ($t in $Tweaks) {
  switch ($t) {
    'DisableBingInSearch' {
      Invoke-TweakAction -Description "Disable Bing/Web in Windows Search" {
        New-Item -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Force | Out-Null
        Set-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\Explorer" DisableSearchBoxSuggestions 1 -Type DWord
      }
    }
    'ShowFileExtensions' {
      Invoke-TweakAction -Description "Show file extensions in Explorer" {
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" HideFileExt 0 -Type DWord
      }
    }
    'TaskbarSmallIcons' {
      Invoke-TweakAction -Description "Enable small icons on taskbar" {
        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" TaskbarSmallIcons 1 -Type DWord
        Stop-Process -Name explorer -Force
      }
    }
    'DisableTelemetryBasic' {
      Invoke-TweakAction -Description "Reduce basic telemetry" {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" AllowTelemetry 0 -Type DWord
      }
    }
    default {
      Write-Host "Unknown tweak: $t"
    }
  }
}
