if (-not ('CDriveCleaner.EngineProcess' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace CDriveCleaner {
    public sealed class EngineProcess : IDisposable {
        private readonly Process process;
        private readonly StreamWriter writer;
        private readonly object gate = new object();
        private bool disposed;

        private EngineProcess(Process process, StreamWriter writer) {
            this.process = process;
            this.writer = writer;
        }

        public int Id { get { return process.Id; } }
        public bool HasExited {
            get {
                try { return process.HasExited; }
                catch { return true; }
            }
        }

        private static string Quote(string value) {
            if (value == null || value.Length == 0) return "\"\"";
            if (value.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '\"' }) < 0) return value;
            var result = new StringBuilder();
            result.Append('\"');
            int slashes = 0;
            foreach (char character in value) {
                if (character == '\\') {
                    slashes++;
                } else if (character == '\"') {
                    result.Append('\\', slashes * 2 + 1);
                    result.Append('\"');
                    slashes = 0;
                } else {
                    result.Append('\\', slashes);
                    result.Append(character);
                    slashes = 0;
                }
            }
            result.Append('\\', slashes * 2);
            result.Append('\"');
            return result.ToString();
        }

        private void WriteLine(string line) {
            if (line == null) return;
            lock (gate) {
                if (!disposed) writer.WriteLine(line);
            }
        }

        private void CloseWriter() {
            lock (gate) {
                if (disposed) return;
                disposed = true;
                writer.Flush();
                writer.Dispose();
            }
        }

        public static EngineProcess Start(string fileName, string[] arguments, string workingDirectory, string logPath) {
            var directory = Path.GetDirectoryName(logPath);
            if (!String.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);
            var stream = new FileStream(logPath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite);
            var writer = new StreamWriter(stream, new UTF8Encoding(false));
            writer.AutoFlush = true;

            var startInfo = new ProcessStartInfo();
            startInfo.FileName = fileName;
            startInfo.Arguments = String.Join(" ", Array.ConvertAll(arguments, Quote));
            startInfo.WorkingDirectory = workingDirectory;
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;
            startInfo.StandardOutputEncoding = Encoding.UTF8;
            startInfo.StandardErrorEncoding = Encoding.UTF8;

            var process = new Process();
            process.StartInfo = startInfo;
            var managed = new EngineProcess(process, writer);
            process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs args) { managed.WriteLine(args.Data); };
            process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs args) { managed.WriteLine(args.Data); };
            if (!process.Start()) {
                writer.Dispose();
                throw new InvalidOperationException("The engine process did not start.");
            }
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            return managed;
        }

        public int Complete() {
            process.WaitForExit();
            int exitCode = process.ExitCode;
            CloseWriter();
            process.Dispose();
            return exitCode;
        }

        public long Cancel(int timeoutMilliseconds) {
            var timer = Stopwatch.StartNew();
            if (!HasExited) {
                process.Kill();
                if (!process.WaitForExit(timeoutMilliseconds)) {
                    throw new TimeoutException("The engine process did not stop within the cancellation timeout.");
                }
            }
            process.WaitForExit();
            timer.Stop();
            CloseWriter();
            process.Dispose();
            return timer.ElapsedMilliseconds;
        }

        public void Dispose() {
            if (!HasExited) {
                try { Cancel(2000); } catch { }
                return;
            }
            try { process.WaitForExit(); } catch { }
            CloseWriter();
            process.Dispose();
        }
    }
}
'@
}

function Start-CDriveEngineProcess {
    param(
        [string]$EnginePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$LogPath
    )

    $processArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $EnginePath) + @($Arguments)
    return [CDriveCleaner.EngineProcess]::Start('powershell.exe', $processArguments, $WorkingDirectory, $LogPath)
}
