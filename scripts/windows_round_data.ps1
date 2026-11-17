param(
  [Parameter(Mandatory = $true)][ValidateSet('list', 'save', 'clear', 'restore')][string]$Action,
  [string]$SaveDir = ''
)
# Saves, clears and restores the Windows debug data of Open Authenticator around a test round (#132,
# docs/test-plan.md section 6): the Credential Manager entries app.openauthenticator.debug*, the two debug
# files in %APPDATA%\Skyost\Open Authenticator, and the debug backups in Documents.
#   list     show what is there
#   save     copy it to $SaveDir (refuses if a save is already there)
#   clear    delete it, for a fresh install of the debug build type
#   restore  put the save back, check it byte for byte, then rename the save folder
# Run it in Windows PowerShell 5.1: powershell -File scripts\windows_round_data.ps1 -Action list
$ErrorActionPreference = 'Stop'
if ($SaveDir -eq '') {
  $SaveDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\build\round-saved'
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class OaCred {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct CREDENTIAL {
    public int Flags; public int Type; public string TargetName; public string Comment;
    public long LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob;
    public int Persist; public int AttributeCount; public IntPtr Attributes;
    public string TargetAlias; public string UserName;
  }
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern bool CredEnumerateW(string filter, int flags, out int count, out IntPtr creds);
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern bool CredWriteW(ref CREDENTIAL cred, int flags);
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool CredDeleteW(string target, int type, int flags);
  [DllImport("advapi32.dll")]
  static extern void CredFree(IntPtr buffer);
  public class Entry { public string Target; public int Type; public int Persist; public string User; public string Blob; public int Attributes; }
  public static List<Entry> List(string filter) {
    List<Entry> result = new List<Entry>();
    int count; IntPtr creds;
    if (!CredEnumerateW(filter, 0, out count, out creds)) {
      int err = Marshal.GetLastWin32Error();
      if (err == 1168) return result; // ERROR_NOT_FOUND
      throw new System.ComponentModel.Win32Exception(err);
    }
    for (int i = 0; i < count; i++) {
      IntPtr p = Marshal.ReadIntPtr(creds, i * IntPtr.Size);
      CREDENTIAL c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
      byte[] blob = new byte[c.CredentialBlobSize];
      if (c.CredentialBlobSize > 0) Marshal.Copy(c.CredentialBlob, blob, 0, c.CredentialBlobSize);
      result.Add(new Entry { Target = c.TargetName, Type = c.Type, Persist = c.Persist, User = c.UserName, Blob = Convert.ToBase64String(blob), Attributes = c.AttributeCount });
    }
    CredFree(creds);
    return result;
  }
  public static void Write(Entry e) {
    byte[] blob = Convert.FromBase64String(e.Blob);
    CREDENTIAL c = new CREDENTIAL { Type = e.Type, TargetName = e.Target, Persist = e.Persist, UserName = e.User, CredentialBlobSize = blob.Length };
    c.CredentialBlob = Marshal.AllocHGlobal(Math.Max(blob.Length, 1));
    try {
      Marshal.Copy(blob, 0, c.CredentialBlob, blob.Length);
      if (!CredWriteW(ref c, 0)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    } finally { Marshal.FreeHGlobal(c.CredentialBlob); }
  }
}
'@

$filter = 'app.openauthenticator.debug*'
$appData = Join-Path $env:APPDATA 'Skyost\Open Authenticator'
$debugFiles = @('app_debug.sqlite', 'shared_preferences_debug.json')
$backups = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Open Authenticator Backups (Debug)'

function Show-State {
  $entries = [OaCred]::List($filter)
  "Credentials ($($entries.Count)):"
  foreach ($e in $entries) { "  $($e.Target) type=$($e.Type) persist=$($e.Persist) attrs=$($e.Attributes) blob=$($e.Blob.Length) b64 chars" }
  "Files:"
  foreach ($f in $debugFiles) { $p = Join-Path $appData $f; if (Test-Path $p) { "  $f $((Get-Item $p).Length) bytes" } }
  "Backups in ${backups}:"
  if (Test-Path $backups) { Get-ChildItem $backups | ForEach-Object { "  $($_.Name) $($_.Length) bytes" } }
}

switch ($Action) {
  'list' { Show-State }
  'save' {
    if (Test-Path (Join-Path $SaveDir 'credentials.json')) { throw "A save already exists in ${SaveDir}: restore it first." }
    New-Item -ItemType Directory -Force (Join-Path $SaveDir 'files'), (Join-Path $SaveDir 'backups') | Out-Null
    $entries = [OaCred]::List($filter)
    if ($entries.Count -eq 0) { '[]' | Out-File -Encoding utf8 (Join-Path $SaveDir 'credentials.json') }
    else { ConvertTo-Json -InputObject @($entries) | Out-File -Encoding utf8 (Join-Path $SaveDir 'credentials.json') }
    foreach ($f in $debugFiles) { $p = Join-Path $appData $f; if (Test-Path $p) { Copy-Item $p (Join-Path $SaveDir 'files') } }
    if (Test-Path $backups) { Get-ChildItem $backups -File | Copy-Item -Destination (Join-Path $SaveDir 'backups') }
    $saved = Get-Content -Raw (Join-Path $SaveDir 'credentials.json') | ConvertFrom-Json
    "Saved $(@($saved).Count) credentials, files and backups to $SaveDir"
  }
  'clear' {
    foreach ($e in [OaCred]::List($filter)) { [void][OaCred]::CredDeleteW($e.Target, $e.Type, 0) }
    foreach ($f in $debugFiles) { $p = Join-Path $appData $f; if (Test-Path $p) { Remove-Item $p } }
    if (Test-Path $backups) { Get-ChildItem $backups -File | Remove-Item }
    'Cleared.'
  }
  'restore' {
    $json = Join-Path $SaveDir 'credentials.json'
    if (-not (Test-Path $json)) { throw "No save in $SaveDir." }
    foreach ($e in [OaCred]::List($filter)) { [void][OaCred]::CredDeleteW($e.Target, $e.Type, 0) }
    foreach ($s in @(Get-Content -Raw $json | ConvertFrom-Json)) {
      if ($null -eq $s) { continue }
      $e = New-Object OaCred+Entry
      $e.Target = $s.Target; $e.Type = $s.Type; $e.Persist = $s.Persist; $e.User = $s.User; $e.Blob = $s.Blob
      [OaCred]::Write($e)
    }
    foreach ($f in $debugFiles) { $p = Join-Path $appData $f; if (Test-Path $p) { Remove-Item $p } }
    Get-ChildItem (Join-Path $SaveDir 'files') -File | Copy-Item -Destination $appData
    if (Test-Path $backups) { Get-ChildItem $backups -File | Remove-Item } else { New-Item -ItemType Directory $backups | Out-Null }
    Get-ChildItem (Join-Path $SaveDir 'backups') -File | Copy-Item -Destination $backups
    # Verify against the save before removing it.
    $now = [OaCred]::List($filter)
    $before = @(Get-Content -Raw $json | ConvertFrom-Json) | Where-Object { $null -ne $_ }
    foreach ($s in $before) {
      $match = $now | Where-Object { $_.Target -eq $s.Target -and $_.Blob -eq $s.Blob }
      if (-not $match) { throw "Restore check failed for $($s.Target)" }
    }
    foreach ($f in $debugFiles) {
      $a = Join-Path $SaveDir "files\$f"; $b = Join-Path $appData $f
      if ((Test-Path $a) -and ((Get-FileHash $a).Hash -ne (Get-FileHash $b).Hash)) { throw "Restore check failed for $f" }
    }
    Rename-Item $SaveDir ("$SaveDir-restored-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    'Restored and verified.'
  }
}
