# GL!TCH: make the /host installer template from the live GlitchHost.msi.
# Adds property GLITCHHOSTCODE (a fixed-length placeholder the server swaps for a one-time code per download)
# and one deferred SYSTEM step after the service starts: GlitchHost.exe --assign --token [GLITCHHOSTCODE].
# No PowerShell at install time for this step.
#   powershell -ExecutionPolicy Bypass -File host-msi.ps1 -In GlitchHost.msi -Out GlitchHost-host.msi
param([Parameter(Mandatory)] [string]$In, [Parameter(Mandatory)] [string]$Out)
$ErrorActionPreference = 'Stop'
$Placeholder = 'GLH-CODE-PLACEHOLDER-' + ('X' * 27)   # 48 characters, the length of a code
$In = (Resolve-Path $In).Path
if ([IO.Path]::GetFullPath($Out) -eq $In) { throw 'Write to a new file; the original stays untouched.' }
Copy-Item $In $Out -Force
$Out = (Resolve-Path $Out).Path

$wi = New-Object -ComObject WindowsInstaller.Installer
$db = $wi.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $wi, @($Out, 1))
function Run($sql, [object[]]$params) {
    $v = $db.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $db, @($sql))
    $rec = $null
    if ($params) {
        $rec = $wi.GetType().InvokeMember('CreateRecord', 'InvokeMethod', $null, $wi, @($params.Count))
        for ($k = 0; $k -lt $params.Count; $k++) {
            $prop = if ($params[$k] -is [int]) { 'IntegerData' } else { 'StringData' }
            $rec.GetType().InvokeMember($prop, 'SetProperty', $null, $rec, @(($k + 1), $params[$k]))
        }
    }
    $v.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $v, @($rec)) | Out-Null
    $r = if ($sql -like 'SELECT*') { $v.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $v, $null) }
    $v.GetType().InvokeMember('Close', 'InvokeMethod', $null, $v, $null) | Out-Null
    , $r
}
function One($sql) { $r = Run $sql; if ($r) { $r.GetType().InvokeMember('StringData', 'GetProperty', $null, $r, 1) } }

if (One "SELECT Action FROM CustomAction WHERE Action='GlitchJoinGroup'") { throw 'This MSI is already patched.' }
if (-not (One "SELECT File FROM File WHERE File='App.exe'")) { throw 'GlitchHost.exe (File App.exe) not found; not patching.' }
$start = [int](One "SELECT Sequence FROM InstallExecuteSequence WHERE Action='CreateStartService'")
$fin = [int](One "SELECT Sequence FROM InstallExecuteSequence WHERE Action='InstallFinalize'")
if (-not $start -or $start -ge $fin) { throw 'CreateStartService / InstallFinalize not where expected; not patching.' }

# InstallFinalize and everything after it move up by 10, so the new step fits right before it.
$v = $db.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $db, @("SELECT Action, Sequence FROM InstallExecuteSequence"))
$v.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $v, $null) | Out-Null
$late = @()
while ($r = $v.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $v, $null)) {
    $s = [int]$r.GetType().InvokeMember('IntegerData', 'GetProperty', $null, $r, 2)
    if ($s -ge $fin) { $late += , @($r.GetType().InvokeMember('StringData', 'GetProperty', $null, $r, 1), $s) }
}
$v.GetType().InvokeMember('Close', 'InvokeMethod', $null, $v, $null) | Out-Null
foreach ($a in $late) { Run "UPDATE InstallExecuteSequence SET Sequence=$($a[1] + 10) WHERE Action='$($a[0])'" | Out-Null }

Run 'INSERT INTO `Property` (`Property`, `Value`) VALUES (?, ?)' @('GLITCHHOSTCODE', $Placeholder) | Out-Null
# 3154 = run an installed exe (18), ignore its exit code (64), deferred (1024), as SYSTEM (2048)
Run 'INSERT INTO `CustomAction` (`Action`, `Type`, `Source`, `Target`) VALUES (?, ?, ?, ?)' @('GlitchJoinGroup', 3154, 'App.exe', '--assign --token [GLITCHHOSTCODE] --note GlitchHost') | Out-Null
Run 'INSERT INTO `InstallExecuteSequence` (`Action`, `Condition`, `Sequence`) VALUES (?, ?, ?)' @('GlitchJoinGroup', 'GLITCHHOSTCODE AND NOT (REMOVE="ALL")', $fin) | Out-Null
$db.GetType().InvokeMember('Commit', 'InvokeMethod', $null, $db, $null) | Out-Null
[Runtime.InteropServices.Marshal]::ReleaseComObject($db) | Out-Null
[Runtime.InteropServices.Marshal]::ReleaseComObject($wi) | Out-Null
[GC]::Collect(); [GC]::WaitForPendingFinalizers()

# The server swaps the placeholder bytes in place: check-msi.py (run it next, in a new process,
# since this one may still hold the file) confirms it sits in the file exactly once, in one piece.
"written: $Out"
