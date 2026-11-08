# Per-user installation. Run explicitly to make this app the tuist: handler.
param([Parameter(Mandatory=$true)][string]$Binary)
$ErrorActionPreference = 'Stop'
$installDir = Join-Path $env:LOCALAPPDATA 'TuistDesktop'
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
$destination = Join-Path $installDir 'Tuist.exe'
Copy-Item -LiteralPath $Binary -Destination $destination -Force

# Never claim http/https, and never require elevation or alter HKLM.
$protocol = 'HKCU:\Software\Classes\tuist'
New-Item -Path $protocol -Force | Out-Null
Set-Item -Path $protocol -Value 'URL:Tuist'
New-ItemProperty -Path $protocol -Name 'URL Protocol' -Value '' -Force | Out-Null
$command = New-Item -Path "$protocol\shell\open\command" -Force
Set-Item -Path $command.PSPath -Value ('"{0}" "%1"' -f $destination)

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'Tuist.lnk'))
$shortcut.TargetPath = $destination
$shortcut.Save()
Write-Output "Installed Tuist in $installDir and registered tuist: links."
