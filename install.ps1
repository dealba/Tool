<#
  H4N53N Tool – Windows Utility (WPF) med profiler og tweaks.
#>

param(
  [switch]$DryRun,
  [switch]$Silent = $true,
  [string]$BaseUrl
)

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
    foreach ($a in $args) { $null = $psi.ArgumentList.Add($a) }
    $psi.Verb = "runas"
    [Diagnostics.Process]::Start($psi) | Out-Null
    exit
  }
}
Ensure-Admin

Write-Log -Message "$($Script:ToolName) start. DryRun=$DryRun Silent=$Silent"

# Kræv winget
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Log -Message "winget ikke fundet. Installer 'App Installer' fra Microsoft Store." -Level "ERROR"
  throw "winget mangler"
}

# Indlæs profiler lokalt eller remote
function Get-ProfileJson {
  param([string]$Name)
  $local = Join-Path $ScriptRoot "profiles\apps-$Name.json"
  if (Test-Path $local) {
    return Get-Content $local -Raw | ConvertFrom-Json
  } elseif ($BaseUrl) {
    $url = ($BaseUrl.TrimEnd('/')) + "/profiles/apps-$Name.json"
    Write-Log -Message "Henter profil: $url"
    $txt = (Invoke-WebRequest -UseBasicParsing -Uri $url).Content
    return $txt | ConvertFrom-Json
  } else {
    throw "Profil '$Name' ikke fundet lokalt og BaseUrl er ikke sat."
  }
}

function Invoke-Tweaks {
  param([string[]]$SelectedTweaks)
  if (-not $SelectedTweaks -or $SelectedTweaks.Count -eq 0) { return }
  $tw = Join-Path $ScriptRoot 'tweaks.ps1'
  & powershell -NoProfile -ExecutionPolicy Bypass -File $tw -Tweaks $SelectedTweaks -DryRun:$DryRun
}

function Install-Winget {
  param([string]$Id, [switch]$SilentInstall)
  $args = @("install","--exact","--id",$Id,"--accept-package-agreements","--accept-source-agreements")
  if ($SilentInstall) { $args += "--silent" }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "winget"
  foreach ($a in $args) { $null = $psi.ArgumentList.Add($a) }
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute        = $false
  $proc = [System.Diagnostics.Process]::Start($psi)
  $stdout = $proc.StandardOutput.ReadToEnd()
  $stderr = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()
  if ($stdout) { Write-Log -Message ($stdout.Trim()) -Level "OUT" }
  if ($stderr) { Write-Log -Message ($stderr.Trim()) -Level "ERR" }
  return $proc.ExitCode
}

# Prøv at loade WPF (PowerShell 5.1)
$UseWpf = $true
try { Add-Type -AssemblyName PresentationFramework } catch { $UseWpf = $false }

# Data
$profiles = @('essentials','dev','gaming')
$appsByProfile = @{}
foreach ($p in $profiles) {
  try { $appsByProfile[$p] = Get-ProfileJson -Name $p } catch { Write-Log -Message $_ -Level "ERROR" }
}

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
$allApps = $allApps | Sort-Object Id -Unique

# Tweak-liste
$allTweaks = @(
  @{ Key='DisableBingInSearch';   Label='Slå Bing-søgning i Start/Search fra' },
  @{ Key='ShowFileExtensions';    Label='Vis filendelser i Explorer' },
  @{ Key='TaskbarSmallIcons';     Label='Små ikoner på taskbar' },
  @{ Key='DisableTelemetryBasic'; Label='Reducer basal telemetri' }
)

if ($UseWpf) {
  # XAML GUI
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
      <CheckBox x:Name="chkDryRun" Content="Dry-Run" Margin="20,0,0,0"/>
      <CheckBox x:Name="chkSilent" Content="Silent install" Margin="12,0,0,0" IsChecked="True"/>
    </StackPanel>
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="2*"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <GroupBox Header="Apps">
        <ListView x:Name="lvApps" SelectionMode="Extended">
          <ListView.View>
            <GridView>
              <GridViewColumn Header="Navn" DisplayMemberBinding="{Binding Name}" Width="230"/>
              <GridViewColumn Header="Id"   DisplayMemberBinding="{Binding Id}"   Width="240"/>
              <GridViewColumn Header="Profil" DisplayMemberBinding="{Binding Profile}" Width="90"/>
            </GridView>
          </ListView.View>
        </ListView>
      </GroupBox>
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
  $lblStat  = $win.FindName('lblStatus')
  $btnInst  = $win.FindName('btnInstall')
  $btnClose = $win.FindName('btnClose')

  # Fyld app-listen
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

  # Klik-håndterere
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

    $lblStatus.Text = "Arbejder... se log."
    if ($selectedTweaks.Count -gt 0) {
      Write-Log -Message ("Tweaks valgt: " + ($selectedTweaks -join ', '))
      Invoke-Tweaks -SelectedTweaks $selectedTweaks
    }

    foreach ($app in $sel) {
      if ($chkDry.IsChecked -or $DryRun) {
        Write-Log -Message ("[DRY-RUN] winget install --id {0}" -f $app.Id)
      } else {
        Write-Log -Message ("Installerer: {0} ({1})..." -f $app.Name, $app.Id)
        $code = Install-Winget -Id $app.Id -SilentInstall:($chkSil.IsChecked)
        if ($code -eq 0) {
          Write-Log -Message ("OK: {0} installeret." -f $app.Name)
        } else {
          Write-Log -Message ("FEJL: {0} kunne ikke installeres." -f $app.Name) -Level "ERROR"
        }
      }
    }

    $lblStatus.Text = "Færdig."
  })

  $btnClose.Add_Click({ $win.Close() })
  $null = $win.ShowDialog()
}
else {
  # Fallback uden WPF
  $selected = $allApps | Select-Object Name, Id, Profile | Out-GridView -Title "$($Script:ToolName) – vælg apps" -PassThru
  if (-not $selected) { Write-Log -Message "Ingen apps valgt. Stopper."; return }
  foreach ($app in $selected) {
    if ($DryRun) {
      Write-Log -Message ("[DRY-RUN] winget install --id {0}" -f $app.Id)
    } else {
      Write-Log -Message ("Installerer: {0} ({1})..." -f $app.Name, $app.Id)
      $code = Install-Winget -Id $app.Id -SilentInstall:$Silent
      if ($code -eq 0) {
        Write-Log -Message ("OK: {0} installeret." -f $app.Name)
      } else {
        Write-Log -Message ("FEJL: {0} kunne ikke installeres." -f $app.Name) -Level "ERROR"
      }
    }
  }
}
