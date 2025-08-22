<#
  H4N53N Tool – Minimal Windows Utility (WPF) med profiler og tweaks.
  Bootstrap (kør som admin i PowerShell):
    iwr -useb https://yourdomain.tld/H4N53N-Tool/install.ps1 | iex
#>

param(
  [switch]$DryRun,
  [switch]$Silent = $true,
  [string]$BaseUrl # valgfri. Hvis sat, hentes profiler/tweaks remote (fx GitHub raw)
)

# ── Utils ──────────────────────────────────────────────────────────────────────
$ErrorActionPreference = 'Stop'
$Script:ToolName = 'H4N53N Tool'
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

function Write-Log {
  param([string]$Message, [string]$Level = "INFO")
  if (-not $Script:LogFile) {
    $logDir = Join-Path $env:ProgramData 'H4N53N-Tool\Logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $Script:LogFile = Join-Path $logDir ("install_{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))
  }
  $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message
  Write-Host $line
  Add-Content -LiteralPath $Script:LogFile -Value $line
}

function Ensure-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = [Security.Principal.WindowsPrincipal]$id
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "Genstarter $($Script:ToolName) som administrator..."
    $psi = New-Object System.Diagnostics.ProcessStartInfo "powershell"
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($DryRun) { $args += '-DryRun' }
    if ($Silent) { $args += '-Silent' }
    if ($BaseUrl) { $args += @('-BaseUrl',"`"$BaseUrl`"") }
    $psi.ArgumentList.AddRange($args)
    $psi.Verb = "runas"
    [Diagnostics.Process]::Start($psi) | Out-Null
    exit
  }
}
Ensure-Admin

Write-Log "$($Script:ToolName) start. DryRun=$DryRun Silent=$Silent"

# Winget check
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Log "winget ikke fundet. Installer 'App Installer' fra Microsoft Store." "ERROR"
  throw "winget mangler"
}

# ── Hent/json helper (lokalt eller remote) ─────────────────────────────────────
function Get-ProfileJson {
  param([string]$Name)
  $local = Join-Path $ScriptRoot "profiles\apps-$Name.json"
  if (Test-Path $local) {
    return Get-Content $local -Raw | ConvertFrom-Json
  }
  elseif ($BaseUrl) {
    $url = ($BaseUrl.TrimEnd('/')) + "/profiles/apps-$Name.json"
    Write-Log "Henter profil: $url"
    $txt = (Invoke-WebRequest -UseBasicParsing -Uri $url).Content
    return $txt | ConvertFrom-Json
  }
  else {
    throw "Profil '$Name' ikke fundet lokalt og BaseUrl er ikke sat."
  }
}

function Invoke-Tweaks {
  param([string[]]$SelectedTweaks)

  # Kør tweaks.ps1 lokalt eller remote
  if ($BaseUrl -and -not (Test-Path (Join-Path $ScriptRoot 'tweaks.ps1'))) {
    $url = ($BaseUrl.TrimEnd('/')) + "/tweaks.ps1"
    $tmp = Join-Path $env:TEMP "h4n53n_tweaks.ps1"
    Write-Log "Henter tweaks.ps1: $url"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp
    & powershell -NoProfile -ExecutionPolicy Bypass -File $tmp -Tweaks $SelectedTweaks -DryRun:$DryRun
  } else {
    $tw = Join-Path $ScriptRoot 'tweaks.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $tw -Tweaks $SelectedTweaks -DryRun:$DryRun
  }
}

# ── Installationsfunktion ─────────────────────────────────────────────────────
function Install-Winget {
  param([string]$Id, [switch]$SilentInstall)
  $args = @("install","--exact","--id",$Id,"--accept-package-agreements","--accept-source-agreements")
  if ($SilentInstall) { $args += "--silent" }

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "winget"
  $psi.ArgumentList.AddRange($args)
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute        = $false
  $proc = [System.Diagnostics.Process]::Start($psi)
  $stdout = $proc.StandardOutput.ReadToEnd()
  $stderr = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()
  if ($stdout) { Write-Log $stdout.Trim() "OUT" }
  if ($stderr) { Write-Log $stderr.Trim() "ERR" }
  return $proc.ExitCode
}

# ── Prøv at loade WPF ─────────────────────────────────────────────────────────
$UseWpf = $true
try {
  Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null
} catch {
  $UseWpf = $false
  Write-Log "WPF ikke tilgængelig. Fald tilbage til Out-GridView." "WARN"
}

# ── Data (profiler + tweaks) ──────────────────────────────────────────────────
$profiles = @('essentials','dev','gaming') # tilpas/udvid
$appsByProfile = @{}
foreach ($p in $profiles) {
  try { $appsByProfile[$p] = Get-ProfileJson -Name $p } catch { Write-Log $_ "ERROR" }
}

# Ensart app-objekter: name,id,source(optional)
$allApps = @()
foreach ($p in $profiles) {
  foreach ($a in ($appsByProfile[$p] | ForEach-Object { $_ })) {
    $allApps += [pscustomobject]@{
      Profile = $p
      Name    = $a.name
      Id      = $a.id
      Source  = if ($a.source) { $a.source } else { 'winget' }
    }
  }
}
# Fjern dubletter (samme Id)
$allApps = $allApps | Sort-Object Id -Unique

# Tweak-liste (skal matche tweaks.ps1)
$allTweaks = @(
  @{ Key='DisableBingInSearch';   Label='Slå Bing-søgning i Start/Search fra' },
  @{ Key='ShowFileExtensions';    Label='Vis filendelser i Explorer' },
  @{ Key='TaskbarSmallIcons';     Label='Små ikoner på taskbar' },
  @{ Key='DisableTelemetryBasic'; Label='Reducer basal telemetri' }
)

# ── GUI (WPF) eller fallback ──────────────────────────────────────────────────
if ($UseWpf) {
  $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="$($Script:ToolName)" Height="540" Width="820" WindowStartupLocation="CenterScreen">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
      <TextBlock Text="$($Script:ToolName)" FontSize="20" FontWeight="Bold" Margin="0,0,12,0"/>
      <TextBlock Text="— vælg apps og tweaks" VerticalAlignment="Center"/>
      <CheckBox x:Name="chkDryRun" Content="Dry-Run" Margin="20,0,0,0"/>
      <CheckBox x:Name="chkSilent" Content="Silent install" Margin="12,0,0,0" IsChecked="True"/>
      <TextBox x:Name="txtSearch" Width="220" Margin="20,0,0,0" ToolTip="Søg i apps"/>
    </StackPanel>

    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="2*"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- Apps -->
      <GroupBox Header="Apps">
        <DockPanel>
          <ListView x:Name="lvApps" SelectionMode="Extended">
            <ListView.View>
              <GridView>
                <GridViewColumn Header="Navn" DisplayMemberBinding="{Binding Name}" Width="230"/>
                <GridViewColumn Header="Id"   DisplayMemberBinding="{Binding Id}"   Width="240"/>
                <GridViewColumn Header="Profil" DisplayMemberBinding="{Binding Profile}" Width="90"/>
              </GridView>
            </ListView.View>
          </ListView>
        </DockPanel>
      </GroupBox>

      <!-- Tweaks -->
      <GroupBox Grid.Column="1" Header="Tweaks" Margin="10,0,0,0">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel x:Name="spTweaks" Margin="6"/>
        </ScrollViewer>
      </GroupBox>
    </Grid>

    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <TextBlock x:Name="lblStatus" VerticalAlignment="Center" Margin="0,0,10,0"/>
      <Button x:Name="btnInstall" Content="Installér valgte" Width="140" Height="30" Margin="0,0,6,0"/>
      <Button x:Name="btnClose" Content="Luk" Width="90" Height="30"/>
    </StackPanel>
  </Grid>
</Window>
"@

  $reader = (New-Object System.Xml.XmlNodeReader ([xml]$xaml))
  $win = [Windows.Markup.XamlReader]::Load($reader)

  $lvApps   = $win.FindName('lvApps')
  $spTweaks = $win.FindName('spTweaks')
  $chkDry   = $win.FindName('chkDryRun')
  $chkSil   = $win.FindName('chkSilent')
  $txtSearch= $win.FindName('txtSearch')
  $lblStat  = $win.FindName('lblStatus')
  $btnInst  = $win.FindName('btnInstall')
  $btnClose = $win.FindName('btnClose')

  # Fyld data
  $collection = New-Object System.Collections.ObjectModel.ObservableCollection[object]
  $allApps | ForEach-Object { $collection.Add($_) }
  $lvApps.ItemsSource = $collection

  # Tweaks checkboxes
  $tweakBoxes = @{}
  foreach ($t in $allTweaks) {
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = $t.Label
    $cb.Tag     = $t.Key
    $cb.Margin  = '4'
    $spTweaks.Children.Add($cb) | Out-Null
    $tweakBoxes[$t.Key] = $cb
  }

  # Søgning
  $txtSearch.Add_TextChanged({
    $q = $txtSearch.Text.Trim()
    $lvApps.Items.Filter = { param($item)
      if ([string]::IsNullOrWhiteSpace($q)) { return $true }
      $item.Name -like "*$q*" -or $item.Id -like "*$q*" -or $item.Profile -like "*$q*"
    }
  })

  # Install
  $btnInst.Add_Click({
    $sel = @($lvApps.SelectedItems)
    $selectedTweaks = @()
    foreach ($kv in $tweakBoxes.GetEnumerator()) {
      if ($kv.Value.IsChecked) { $selectedTweaks += $kv.Key }
    }

    if ($sel.Count -eq 0 -and $selectedTweaks.Count -eq 0) {
      [System.Windows.MessageBox]::Show("Vælg mindst én app eller tweak.","$($Script:ToolName)")
      return
    }

    $lblStat.Text = "Arbejder... se log: $Script:LogFile"
    $btnInst.IsEnabled = $false

    $isDry = $chkDry.IsChecked
    $isSilent = $chkSil.IsChecked

    # Kør tweaks først
    if ($selectedTweaks.Count -gt 0) {
      Write-Log "Tweaks valgt: $($selectedTweaks -join ', ')"
      Invoke-Tweaks -SelectedTweaks $selectedTweaks
    }

    # Kør installationsrunden
    foreach ($app in $sel) {
      if ($app.Source -ne 'winget') {
        Write-Log "Ukendt source '$($app.Source)' for $($app.Name) – springer over." "WARN"
        continue
      }
      if ($isDry) {
        Write-Log "[DRY-RUN] winget install --id $($app.Id)"
        continue
      }
      Write-Log "Installerer: $($app.Name) ($($app.Id))..."
      $code = Install-Winget -Id $app.Id -SilentInstall:$isSilent
      if ($code -eq 0) {
        Write-Log "OK: $($app.Name) installeret."
      } else {
        Write-Log "FEJL ($code): $($app.Name) kunne ikke installeres." "ERROR"
      }
    }

    $lblStat.Text = "Færdig. Log: $Script:LogFile"
    $btnInst.IsEnabled = $true
  })

  $btnClose.Add_Click({ $win.Close() })

  # Init checkbox-states fra parametre
  $chkDry.IsChecked = [bool]$DryRun
  $chkSil.IsChecked = [bool]$Silent

  $win.ShowDialog() | Out-Null
}
else {
  # ── Fallback TUI: Out-GridView
  $selected = $allApps | Select-Object Name, Id, Profile | Out-GridView -Title "$($Script:ToolName) – vælg apps" -PassThru
  if (-not $selected) { Write-Log "Ingen apps valgt. Stopper."; return }

  foreach ($app in $selected) {
    if ($DryRun) { Write-Log "[DRY-RUN] winget install --id $($app.Id)"; continue }
    Write-Log "Installerer: $($app.Name) ($($app.Id))..."
    $code = Install-Winget -Id $app.Id -SilentInstall:$Silent
    if ($code -eq 0) { Write-Log "OK: $($app.Name) installeret." } else { Write-Log "FEJL ($code): $($app.Name)" "ERROR" }
  }
  Write-Log "Færdig."
}
