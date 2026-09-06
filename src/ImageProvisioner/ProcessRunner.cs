using System.Diagnostics;

namespace ImageFactory;

public sealed class ProcessRunner
{
    // Arguments never pass through a shell. Quiet mode suppresses vendor output
    // when it could include onboarding data or runner credentials.
    public async Task<string> Run(string executable, string[] arguments,
        bool quiet = false, IReadOnlyDictionary<string, string>? environment = null,
        int timeoutSeconds = 1800)
    {
        var info = new ProcessStartInfo(executable)
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        foreach (var argument in arguments) info.ArgumentList.Add(argument);
        if (environment is not null)
            foreach (var (key, value) in environment) info.Environment[key] = value;
        using var process = Process.Start(info) ?? throw new InvalidOperationException("Cannot start process.");
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));
        try { await process.WaitForExitAsync(timeout.Token); }
        catch (OperationCanceledException)
        {
            process.Kill(entireProcessTree: true);
            throw new TimeoutException($"{Path.GetFileName(executable)} timed out.");
        }
        var output = await stdout;
        var error = await stderr;
        if (!quiet)
        {
            Console.Write(output);
            Console.Error.Write(error);
        }
        if (process.ExitCode != 0)
            throw new InvalidOperationException($"{Path.GetFileName(executable)} failed with exit code {process.ExitCode}; sensitive output is suppressed in quiet mode.");
        return output.Trim();
    }
}
