using System.Text.Json;
using System.Runtime.Versioning;

namespace ImageFactory;

[SupportedOSPlatform("linux")]
public sealed class Installer(ProcessRunner process)
{
    private const string Root = "/opt/image-factory";
    private static readonly Dictionary<string, string> AptEnvironment = new()
    {
        ["DEBIAN_FRONTEND"] = "noninteractive",
        ["NEEDRESTART_MODE"] = "a"
    };

    private Task<string> Apt(params string[] args) => process.Run("apt-get",
        ["-o", "DPkg::Lock::Timeout=300", "-o", "Acquire::Retries=3", .. args], environment: AptEnvironment);

    public async Task Install(string pinsPath)
    {
        var os = File.ReadAllLines("/etc/os-release").Where(l => l.Contains('='))
            .Select(l => l.Split('=', 2)).ToDictionary(p => p[0], p => p[1].Trim('"'));
        if (os["ID"] != "ubuntu" || await process.Run("dpkg", ["--print-architecture"], true) != "amd64")
            throw new InvalidOperationException("This image build supports Ubuntu amd64 only.");
        var version = os["VERSION_ID"];
        var codename = Policy.UbuntuCodename(version);
        var pins = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(pinsPath))
            ?? throw new InvalidDataException("Invalid package pins.");
        Policy.ValidatePins(pins);
        await AssertUnenrolled();
        if (File.Exists("/usr/sbin/policy-rc.d"))
            throw new InvalidOperationException("Existing policy-rc.d requires review before image customization.");
        // Prevent package post-install scripts from starting/enrolling agents.
        File.WriteAllText("/usr/sbin/policy-rc.d", "#!/bin/sh\nexit 101\n");
        File.SetUnixFileMode("/usr/sbin/policy-rc.d", (UnixFileMode)0x1ED);
        try
        {
            await Apt("update");
            await Apt("install", "-y", "--no-install-recommends", "ca-certificates", "gnupg", "curl",
                "apt-transport-https", "python3", "libplist-utils", "git", version == "24.04" ? "libssl3t64" : "libssl3", "zlib1g", "libstdc++6");
            await Apt("-o", "Dpkg::Options::=--force-confold", "upgrade", "-y");
            Directory.CreateDirectory("/etc/apt/keyrings");
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(120) };
            await Key(client, "docker", "https://download.docker.com/linux/ubuntu/gpg");
            await Key(client, "gitlab-runner", "https://packages.gitlab.com/runner/gitlab-runner/gpgkey");
            await Key(client, "datadog", "https://keys.datadoghq.com/DATADOG_APT_KEY_CURRENT.public");
            await Key(client, "microsoft", "https://packages.microsoft.com/keys/microsoft.asc");
            Repository("docker", $"https://download.docker.com/linux/ubuntu {codename} stable");
            Repository("gitlab-runner", $"https://packages.gitlab.com/runner/gitlab-runner/ubuntu/ {codename} main");
            Repository("datadog", "https://apt.datadoghq.com/ stable 7");
            Repository("microsoft", $"https://packages.microsoft.com/ubuntu/{version}/prod {codename} main");
            await Apt("update");
            var packages = Policy.Packages.Select(p => pins.TryGetValue(p, out var pin) ? $"{p}={pin}" : p).ToArray();
            await Apt(["install", "-y", "--no-install-recommends", .. packages]);
            // Explicitly keep tenant-specific services inactive in the reusable image.
            await process.Run("systemctl", ["disable", "--now", "datadog-agent", "gitlab-runner", "mdatp"]);
            await process.Run("systemctl", ["enable", "docker", "containerd"]);
            await process.Run("systemctl", ["start", "docker"]);
            await Verify();
            var inventory = await process.Run("dpkg-query", ["-W", "-f=${Package}\t${Version}\n"], true);
            File.WriteAllText($"{Root}/packages.tsv", inventory + "\n");
            var resolved = new Dictionary<string, string>();
            foreach (var package in Policy.Packages)
                resolved[package] = await process.Run("dpkg-query", ["-W", "-f=${Version}", package], true);
            File.WriteAllText($"{Root}/resolved-package-pins.json", JsonSerializer.Serialize(resolved, new JsonSerializerOptions { WriteIndented = true }));
            File.SetUnixFileMode($"{Root}/packages.tsv", (UnixFileMode)0x1A4);
            File.SetUnixFileMode($"{Root}/resolved-package-pins.json", (UnixFileMode)0x1A4);
        }
        finally { File.Delete("/usr/sbin/policy-rc.d"); }
    }

    private static async Task Key(HttpClient client, string name, string url)
    {
        var data = await client.GetStringAsync(url);
        if (!data.Contains("-----BEGIN PGP PUBLIC KEY BLOCK-----", StringComparison.Ordinal))
            throw new InvalidDataException($"Invalid signing key for {name}.");
        var path = $"/etc/apt/keyrings/{name}.asc";
        File.WriteAllText(path, data);
        File.SetUnixFileMode(path, (UnixFileMode)0x1A4);
    }

    private static void Repository(string name, string repository) => File.WriteAllText(
        $"/etc/apt/sources.list.d/image-factory-{name}.list",
        $"deb [arch=amd64 signed-by=/etc/apt/keyrings/{name}.asc] {repository}\n");

    public async Task Verify()
    {
        foreach (var package in Policy.Packages)
        {
            var status = await process.Run("dpkg-query", ["-W", "-f=${Status}", package], true);
            if (status != "install ok installed") throw new InvalidOperationException($"Package not installed: {package}.");
        }
        await process.Run("docker", ["version"]);
        await process.Run("docker", ["compose", "version"]);
        await process.Run("docker", ["buildx", "version"]);
        await process.Run("gitlab-runner", ["--version"]);
        await process.Run("datadog-agent", ["version"]);
        await process.Run("mdatp", ["--help"]);
        await AssertUnenrolled();
        Console.WriteLine("Package and CLI checks passed. This is not a CIS compliance assessment.");
    }

    private static Task AssertUnenrolled()
    {
        foreach (var path in new[] { "/etc/opt/microsoft/mdatp/mdatp_onboard.json", "/etc/gitlab-runner/config.toml", "/etc/datadog-agent/datadog.yaml" })
        {
            if (!File.Exists(path)) continue;
            var text = File.ReadAllText(path);
            if (path.EndsWith("mdatp_onboard.json", StringComparison.Ordinal) ||
                (path.EndsWith("config.toml", StringComparison.Ordinal) && text.Contains("[[runners]]", StringComparison.Ordinal)) ||
                (path.EndsWith("datadog.yaml", StringComparison.Ordinal) &&
                 text.Split('\n').Any(l => l.TrimStart().StartsWith("api_key:", StringComparison.Ordinal) &&
                     !string.IsNullOrWhiteSpace(l.Split(':', 2)[1]))))
                throw new InvalidOperationException("An enrolled/configured agent was found. Build from a clean unenrolled source.");
        }
        return Task.CompletedTask;
    }

    public async Task Seal()
    {
        await AssertUnenrolled();
        await process.Run("systemctl", ["stop", "docker.socket", "docker", "containerd"]);
        await process.Run("systemctl", ["disable", "--now", "datadog-agent", "gitlab-runner", "mdatp"]);
        await Apt("clean");
        // No docker pulls occur during the build; avoid copying a daemon identity.
        foreach (var path in new[] { "/var/lib/docker/engine-id", "/etc/docker/key.json", "/etc/gitlab-runner/.runner_system_id" }) File.Delete(path);
        await process.Run("cloud-init", ["clean", "--logs", "--machine-id", "--seed"]);
        // This must be the last VM customization. Do not boot again before capture.
        await process.Run("waagent", ["-deprovision+user", "-force"]);
    }
}
