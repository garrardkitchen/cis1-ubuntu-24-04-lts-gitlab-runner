using System.IO.Compression;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Runtime.Versioning;

namespace ImageFactory;

[SupportedOSPlatform("linux")]
public sealed class Enrollment(ProcessRunner process)
{
    // Run these only on a deployed VM, never in the Packer build.
    public async Task Defender(string zipPath)
    {
        Policy.RequirePrivateFile(zipPath);
        using var zip = ZipFile.OpenRead(zipPath);
        var entry = Policy.SelectLinuxScript(zip);
        var folder = $"/run/image-factory-mde-{Guid.NewGuid():N}";
        Directory.CreateDirectory(folder, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        try
        {
            var script = Path.Combine(folder, Policy.LinuxOnboardingScript);
            await using (var destination = PrivateFile(script))
            await using (var source = entry.Open())
                await source.CopyToAsync(destination);
            await process.Run("systemctl", ["enable", "--now", "mdatp"]);
            // Execute Microsoft's original Linux script, without rewriting it.
            await process.Run("python3", [script], quiet: true);
            await process.Run("systemctl", ["restart", "mdatp"]);
            var organization = await process.Run("mdatp", ["health", "--field", "org_id"], true);
            if (!Guid.TryParse(organization.Trim('"'), out _))
                throw new InvalidOperationException("Defender onboarding did not return a valid organization ID.");
            Console.WriteLine("Defender is onboarded. Check healthy, definitions_status and real_time_protection_enabled after definitions download, then confirm the device in the portal.");
        }
        finally { Directory.Delete(folder, recursive: true); }
    }

    public async Task Datadog(string configPath)
    {
        var config = ReadPrivate<DatadogSettings>(configPath);
        if (!Regex.IsMatch(config.ApiKey, "^[a-fA-F0-9]{32}$", RegexOptions.CultureInvariant))
            throw new ArgumentException("Invalid Datadog API key format.");
        string[] sites = ["datadoghq.com", "datadoghq.eu", "us3.datadoghq.com", "us5.datadoghq.com", "ap1.datadoghq.com", "ap2.datadoghq.com", "ddog-gov.com"];
        if (!sites.Contains(config.Site)) throw new ArgumentException("Select a supported Datadog site.");
        var destination = "/etc/datadog-agent/datadog.yaml";
        var temporary = destination + ".image-factory-new";
        var yaml = $"api_key: {JsonSerializer.Serialize(config.ApiKey)}\nsite: {JsonSerializer.Serialize(config.Site)}\n";
        await using (var stream = PrivateFile(temporary))
        await using (var writer = new StreamWriter(stream))
            await writer.WriteAsync(yaml);
        await process.Run("chown", ["root:dd-agent", temporary]);
        File.SetUnixFileMode(temporary, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.GroupRead);
        File.Move(temporary, destination, overwrite: true);
        await process.Run("systemctl", ["enable", "--now", "datadog-agent"]);
        await process.Run("systemctl", ["restart", "datadog-agent"]);
        Console.WriteLine("Datadog configured. Confirm this VM reports in your Datadog site.");
    }

    public async Task Runner(string configPath)
    {
        var config = ReadPrivate<RunnerSettings>(configPath);
        if (!Uri.TryCreate(config.Url, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
            !string.IsNullOrEmpty(uri.UserInfo) || !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment))
            throw new ArgumentException("GitLab URL must be HTTPS without embedded credentials, query or fragment.");
        if (!config.AuthenticationToken.StartsWith("glrt-", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(config.Name))
            throw new ArgumentException("Provide a runner authentication token (glrt-) and a name.");
        if (!Regex.IsMatch(config.DockerImage, @"^[A-Za-z0-9][A-Za-z0-9._:/\-]*@sha256:[a-f0-9]{64}$", RegexOptions.CultureInvariant))
            throw new ArgumentException("Pin the job image by sha256 digest.");
        const string runnerConfig = "/etc/gitlab-runner/config.toml";
        if (File.Exists(runnerConfig) && File.ReadAllText(runnerConfig).Contains("[[runners]]", StringComparison.Ordinal))
            throw new InvalidOperationException("Runner already registered; refusing duplicate registration.");
        await process.Run("gitlab-runner", ["register", "--non-interactive"], true, new Dictionary<string, string>
        {
            ["CI_SERVER_URL"] = config.Url,
            ["RUNNER_TOKEN"] = config.AuthenticationToken,
            ["RUNNER_NAME"] = config.Name,
            ["RUNNER_EXECUTOR"] = "docker",
            ["DOCKER_IMAGE"] = config.DockerImage,
            ["DOCKER_PRIVILEGED"] = "false"
        });
        File.SetUnixFileMode(runnerConfig, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        await process.Run("systemctl", ["enable", "--now", "gitlab-runner"]);
        await process.Run("gitlab-runner", ["verify"], true);
        Console.WriteLine("Runner registered. Run a real smoke-test job before admitting workloads.");
    }

    private static T ReadPrivate<T>(string path)
    {
        Policy.RequirePrivateFile(path);
        return JsonSerializer.Deserialize<T>(File.ReadAllText(path), new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        }) ?? throw new InvalidDataException("Invalid settings file.");
    }

    private static FileStream PrivateFile(string path) => new(path, new FileStreamOptions
    {
        Mode = FileMode.CreateNew,
        Access = FileAccess.Write,
        UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite
    });
}

public sealed record DatadogSettings(string ApiKey, string Site);
public sealed record RunnerSettings(string Url, string AuthenticationToken, string DockerImage, string Name);
