# Runs a command with the toolchain paths from dev-env.local (JAVA_HOME, FLUTTER_ROOT).
# Usage: scripts\with-env.ps1 flutter doctor -v
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$config = Join-Path $root 'dev-env.local'

if (-not (Test-Path $config)) {
    Write-Error "$config not found. Copy dev-env.example to dev-env.local and set the paths for this machine."
    exit 1
}

foreach ($line in Get-Content $config) {
    $line = $line.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { continue }
    $key, $value = $line -split '=', 2
    $key = $key.Trim()
    if ($null -eq $value -or $value.Trim() -eq '') { continue }
    $value = $value.Trim()
    switch ($key) {
        'JAVA_HOME' {
            if (-not (Test-Path (Join-Path $value 'bin\java.exe'))) { Write-Error "JAVA_HOME=$value has no bin\java.exe."; exit 1 }
            $env:JAVA_HOME = $value
            $env:Path = (Join-Path $value 'bin') + ';' + $env:Path
        }
        'FLUTTER_ROOT' {
            if (-not (Test-Path (Join-Path $value 'bin'))) { Write-Error "FLUTTER_ROOT=$value has no bin directory."; exit 1 }
            $env:Path = (Join-Path $value 'bin') + ';' + $env:Path
        }
        default { Set-Item -Path "env:$key" -Value $value }
    }
}

# Flutter ignores JAVA_HOME when Android Studio's bundled JBR is installed; its own `jdk-dir` setting wins.
# Keep that (user-global) setting in sync with dev-env.local.
if ($env:JAVA_HOME -and (Get-Command flutter -ErrorAction SilentlyContinue)) {
    $settings = Join-Path $env:APPDATA '.flutter_settings'
    $current = $null
    if (Test-Path $settings) { $current = (Get-Content $settings -Raw | ConvertFrom-Json).'jdk-dir' }
    if ($current -ne $env:JAVA_HOME) {
        Write-Host "with-env: setting flutter jdk-dir to $env:JAVA_HOME"
        flutter config --jdk-dir $env:JAVA_HOME | Out-Null
    }
}

if ($args.Count -eq 0) {
    Write-Output "JAVA_HOME=$env:JAVA_HOME"
    Get-Command java, flutter, dart -ErrorAction SilentlyContinue | ForEach-Object { $_.Source }
    exit 0
}

$command = $args[0]
$rest = @()
if ($args.Count -gt 1) { $rest = $args[1..($args.Count - 1)] }
& $command @rest
exit $LASTEXITCODE
