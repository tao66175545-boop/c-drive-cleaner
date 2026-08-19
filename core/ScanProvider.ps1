$script:CDriveFastScanAvailable = $false
if (-not ('CDriveCleaner.FastDirectorySizer' -as [type])) {
    try {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;

namespace CDriveCleaner {
    public static class FastDirectorySizer {
        public static long GetSize(string root) {
            long total = 0;
            var pending = new Stack<DirectoryInfo>();
            pending.Push(new DirectoryInfo(root));
            while (pending.Count > 0) {
                DirectoryInfo current = pending.Pop();
                try {
                    foreach (FileSystemInfo entry in current.EnumerateFileSystemInfos()) {
                        try {
                            if ((entry.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                            FileInfo file = entry as FileInfo;
                            if (file != null) {
                                total += file.Length;
                                continue;
                            }
                            DirectoryInfo directory = entry as DirectoryInfo;
                            if (directory != null) pending.Push(directory);
                        } catch { }
                    }
                } catch { }
            }
            return total;
        }
    }
}
'@
    } catch {
        $script:CDriveFastScanAvailable = $false
    }
}
if ('CDriveCleaner.FastDirectorySizer' -as [type]) { $script:CDriveFastScanAvailable = $true }

function Get-CDriveLegacyDirectorySize {
    param([string]$Path)

    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { ([int]$_.Attributes -band 0x400) -eq 0 } |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return 0.0 }
    return [double]$sum
}

function Measure-CDrivePathSize {
    param(
        [string]$Path,
        [ValidateSet('Auto', 'Fast', 'Legacy')][string]$Provider = 'Auto'
    )

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return [PSCustomObject]@{ Size = 0.0; Provider = 'None'; ElapsedMilliseconds = 0; ElapsedTicks = 0L }
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return [PSCustomObject]@{ Size = 0.0; Provider = 'None'; ElapsedMilliseconds = 0; ElapsedTicks = 0L } }
    if (-not $item.PSIsContainer) {
        $timer.Stop()
        return [PSCustomObject]@{ Size = [double]$item.Length; Provider = 'File'; ElapsedMilliseconds = $timer.ElapsedMilliseconds; ElapsedTicks = $timer.ElapsedTicks }
    }

    $selected = $Provider
    if ($env:CDRIVE_SCAN_PROVIDER -eq 'legacy') { $selected = 'Legacy' }
    if ($selected -eq 'Auto') { $selected = if ($script:CDriveFastScanAvailable) { 'Fast' } else { 'Legacy' } }
    if ($selected -eq 'Fast' -and -not $script:CDriveFastScanAvailable) { $selected = 'Legacy' }

    $size = if ($selected -eq 'Fast') {
        [double][CDriveCleaner.FastDirectorySizer]::GetSize([System.IO.Path]::GetFullPath($Path))
    } else {
        Get-CDriveLegacyDirectorySize $Path
    }
    $timer.Stop()
    return [PSCustomObject]@{ Size = [double]$size; Provider = $selected; ElapsedMilliseconds = $timer.ElapsedMilliseconds; ElapsedTicks = $timer.ElapsedTicks }
}

function Get-CDriveIncrementalCapability {
    param([string]$Drive = 'C:')

    $volume = Get-Volume -DriveLetter $Drive.TrimEnd(':') -ErrorAction SilentlyContinue
    if (-not $volume -or [string]$volume.FileSystem -ne 'NTFS') {
        return [PSCustomObject]@{ Supported = $false; Reason = 'not-ntfs'; JournalReadable = $false }
    }
    $query = & fsutil usn queryjournal $Drive 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        return [PSCustomObject]@{ Supported = $false; Reason = 'journal-query-denied'; JournalReadable = $false }
    }
    $read = & fsutil usn readjournal $Drive startusn=0 csv 2>&1 | Select-Object -First 1 | Out-String
    $readable = $LASTEXITCODE -eq 0 -and $read -notmatch 'Access is denied'
    return [PSCustomObject]@{
        Supported = [bool]$readable
        Reason = $(if ($readable) { 'available' } else { 'journal-read-denied' })
        JournalReadable = [bool]$readable
    }
}
