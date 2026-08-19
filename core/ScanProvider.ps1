$script:CDriveFastScanAvailable = $false
if (-not ('CDriveCleaner.FastDirectorySizer' -as [type])) {
    try {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

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

    public sealed class UsnJournalState {
        public ulong JournalId { get; set; }
        public long FirstUsn { get; set; }
        public long NextUsn { get; set; }
    }

    public sealed class UsnChangeRecord {
        public ulong FileId { get; set; }
        public ulong ParentFileId { get; set; }
        public long Usn { get; set; }
        public uint Reason { get; set; }
    }

    public static class NtfsIncrementalReader {
        private const uint GenericRead = 0x80000000;
        private const uint ShareRead = 0x00000001;
        private const uint ShareWrite = 0x00000002;
        private const uint ShareDelete = 0x00000004;
        private const uint OpenExisting = 3;
        private const uint BackupSemantics = 0x02000000;
        private const uint FsctlQueryUsnJournal = 0x000900f4;
        private const uint FsctlReadUsnJournal = 0x000900bb;

        [StructLayout(LayoutKind.Sequential)]
        private struct UsnJournalDataV0 {
            public ulong UsnJournalID;
            public long FirstUsn;
            public long NextUsn;
            public long LowestValidUsn;
            public long MaxUsn;
            public ulong MaximumSize;
            public ulong AllocationDelta;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ReadUsnJournalDataV0 {
            public long StartUsn;
            public uint ReasonMask;
            public uint ReturnOnlyOnClose;
            public ulong Timeout;
            public ulong BytesToWaitFor;
            public ulong UsnJournalID;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ByHandleFileInformation {
            public uint FileAttributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(
            string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
            uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool DeviceIoControl(
            SafeFileHandle device, uint controlCode, IntPtr inBuffer, int inBufferSize,
            IntPtr outBuffer, int outBufferSize, out int bytesReturned, IntPtr overlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(
            SafeFileHandle file, out ByHandleFileInformation information);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool GetVolumeInformation(
            string rootPathName, StringBuilder volumeNameBuffer, int volumeNameSize,
            out uint volumeSerialNumber, out uint maximumComponentLength,
            out uint fileSystemFlags, StringBuilder fileSystemNameBuffer, int fileSystemNameSize);

        private static SafeFileHandle OpenVolume(string drive) {
            string normalized = drive.TrimEnd('\\');
            if (!normalized.EndsWith(":")) normalized += ":";
            var handle = CreateFile(@"\\.\" + normalized, GenericRead,
                ShareRead | ShareWrite | ShareDelete, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
            return handle;
        }

        public static UsnJournalState QueryState(string drive) {
            using (SafeFileHandle volume = OpenVolume(drive)) {
                int size = Marshal.SizeOf(typeof(UsnJournalDataV0));
                IntPtr output = Marshal.AllocHGlobal(size);
                try {
                    int returned;
                    if (!DeviceIoControl(volume, FsctlQueryUsnJournal, IntPtr.Zero, 0,
                        output, size, out returned, IntPtr.Zero)) {
                        throw new Win32Exception(Marshal.GetLastWin32Error());
                    }
                    var state = (UsnJournalDataV0)Marshal.PtrToStructure(output, typeof(UsnJournalDataV0));
                    return new UsnJournalState { JournalId = state.UsnJournalID, FirstUsn = state.FirstUsn, NextUsn = state.NextUsn };
                } finally { Marshal.FreeHGlobal(output); }
            }
        }

        public static UsnChangeRecord[] ReadChanges(string drive, ulong journalId, long startUsn, long stopUsn) {
            var records = new List<UsnChangeRecord>();
            using (SafeFileHandle volume = OpenVolume(drive)) {
                int inputSize = Marshal.SizeOf(typeof(ReadUsnJournalDataV0));
                IntPtr input = Marshal.AllocHGlobal(inputSize);
                int outputSize = 1024 * 1024;
                IntPtr output = Marshal.AllocHGlobal(outputSize);
                try {
                    long cursor = startUsn;
                    bool probed = false;
                    while (!probed || cursor < stopUsn) {
                        probed = true;
                        var request = new ReadUsnJournalDataV0 {
                            StartUsn = cursor,
                            ReasonMask = UInt32.MaxValue,
                            ReturnOnlyOnClose = 0,
                            Timeout = 0,
                            BytesToWaitFor = 0,
                            UsnJournalID = journalId
                        };
                        Marshal.StructureToPtr(request, input, false);
                        int returned;
                        if (!DeviceIoControl(volume, FsctlReadUsnJournal, input, inputSize,
                            output, outputSize, out returned, IntPtr.Zero)) {
                            throw new Win32Exception(Marshal.GetLastWin32Error());
                        }
                        if (returned < 8) throw new InvalidDataException("USN journal returned an invalid buffer.");
                        long next = Marshal.ReadInt64(output);
                        int offset = 8;
                        while (offset + 60 <= returned) {
                            int length = Marshal.ReadInt32(output, offset);
                            if (length < 60 || offset + length > returned) throw new InvalidDataException("USN record is malformed.");
                            short major = Marshal.ReadInt16(output, offset + 4);
                            if (major != 2) throw new InvalidDataException("Unsupported USN record version: " + major);
                            long usn = Marshal.ReadInt64(output, offset + 24);
                            if (usn >= stopUsn) break;
                            records.Add(new UsnChangeRecord {
                                FileId = unchecked((ulong)Marshal.ReadInt64(output, offset + 8)),
                                ParentFileId = unchecked((ulong)Marshal.ReadInt64(output, offset + 16)),
                                Usn = usn,
                                Reason = unchecked((uint)Marshal.ReadInt32(output, offset + 40))
                            });
                            offset += length;
                        }
                        if (next <= cursor || next >= stopUsn || returned == 8) break;
                        cursor = next;
                        if (records.Count > 1000000) throw new InvalidDataException("USN change set is too large for an incremental scan.");
                    }
                } finally {
                    Marshal.FreeHGlobal(input);
                    Marshal.FreeHGlobal(output);
                }
            }
            return records.ToArray();
        }

        public static ulong GetFileId(string path) {
            using (SafeFileHandle handle = CreateFile(path, 0, ShareRead | ShareWrite | ShareDelete,
                IntPtr.Zero, OpenExisting, BackupSemantics, IntPtr.Zero)) {
                if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
                ByHandleFileInformation information;
                if (!GetFileInformationByHandle(handle, out information)) throw new Win32Exception(Marshal.GetLastWin32Error());
                return ((ulong)information.FileIndexHigh << 32) | information.FileIndexLow;
            }
        }

        public static ulong[] GetTreeFileIds(string root, int maximumIds) {
            var ids = new HashSet<ulong>();
            var pending = new Stack<DirectoryInfo>();
            pending.Push(new DirectoryInfo(root));
            while (pending.Count > 0) {
                DirectoryInfo current = pending.Pop();
                try { ids.Add(GetFileId(current.FullName)); } catch { }
                if (ids.Count > maximumIds) throw new InvalidDataException("Incremental identity limit exceeded.");
                try {
                    foreach (FileSystemInfo child in current.EnumerateFileSystemInfos()) {
                        try {
                            if ((child.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                            ids.Add(GetFileId(child.FullName));
                            DirectoryInfo directory = child as DirectoryInfo;
                            if (directory != null) pending.Push(directory);
                        } catch { }
                        if (ids.Count > maximumIds) throw new InvalidDataException("Incremental identity limit exceeded.");
                    }
                } catch { }
                if (ids.Count > maximumIds) throw new InvalidDataException("Incremental identity limit exceeded.");
            }
            var result = new ulong[ids.Count];
            ids.CopyTo(result);
            return result;
        }

        public static ulong GetIdentity(string path) { return GetFileId(path); }

        public static string GetVolumeSerial(string drive) {
            string root = drive.TrimEnd('\\') + "\\";
            uint serial, maximumComponentLength, fileSystemFlags;
            var volumeName = new System.Text.StringBuilder(261);
            var fileSystemName = new System.Text.StringBuilder(261);
            if (!GetVolumeInformation(root, volumeName, volumeName.Capacity, out serial,
                out maximumComponentLength, out fileSystemFlags, fileSystemName, fileSystemName.Capacity)) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            return serial.ToString("X8");
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
    try {
        $state = [CDriveCleaner.NtfsIncrementalReader]::QueryState($Drive)
        $null = [CDriveCleaner.NtfsIncrementalReader]::ReadChanges($Drive, $state.JournalId, $state.NextUsn, $state.NextUsn)
        return [PSCustomObject]@{ Supported = $true; Reason = 'available'; JournalReadable = $true; JournalId = $state.JournalId; NextUsn = $state.NextUsn }
    } catch {
        $reason = if ($_.Exception.Message -match '(?i)access.*denied') { 'journal-read-denied' } else { 'journal-read-failed' }
        return [PSCustomObject]@{ Supported = $false; Reason = $reason; JournalReadable = $false }
    }
}
