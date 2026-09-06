using System.IO.Compression;
using System.Text.RegularExpressions;

namespace ImageFactory;

public static partial class Policy
{
    public const string LinuxOnboardingScript = "MicrosoftDefenderATPOnboardingLinuxServer.py";
    public static readonly string[] Packages =
    [
        "docker-ce", "docker-ce-cli", "containerd.io", "docker-buildx-plugin",
        "docker-compose-plugin", "gitlab-runner", "gitlab-runner-helper-images",
        "datadog-agent", "mdatp"
    ];

    public static string UbuntuCodename(string version) => version switch
    {
        "24.04" => "noble",
        "22.04" => "jammy",
        _ => throw new ArgumentException("Only Ubuntu 24.04 and 22.04 are supported.")
    };

    public static void ValidatePins(IReadOnlyDictionary<string, string> pins)
    {
        foreach (var (package, version) in pins)
            if (!Packages.Contains(package) || !VersionPattern().IsMatch(version))
                throw new ArgumentException($"Invalid package or version: {package}.");
        if (pins.TryGetValue("gitlab-runner", out var runner) !=
            pins.TryGetValue("gitlab-runner-helper-images", out var helper) || runner != helper)
            throw new ArgumentException("Pin GitLab Runner and helper images together at the same version.");
    }

    public static ZipArchiveEntry SelectLinuxScript(ZipArchive archive)
    {
        var matches = archive.Entries.Where(e => e.Name == LinuxOnboardingScript).ToArray();
        if (matches.Length != 1)
            throw new InvalidDataException("Expected exactly one MicrosoftDefenderATPOnboardingLinuxServer.py. Download Linux Server / Local Script from Defender.");
        var entry = matches[0];
        if (entry.FullName.Contains("..", StringComparison.Ordinal) ||
            entry.FullName.StartsWith('/') || entry.FullName.Contains('\\') ||
            entry.Length is <= 0 or > 1_048_576)
            throw new InvalidDataException("Invalid onboarding archive entry.");
        return entry;
    }

    public static void RequirePrivateFile(string path)
    {
        if (!OperatingSystem.IsLinux()) throw new PlatformNotSupportedException();
        var info = new FileInfo(path);
        if (!info.Exists || info.LinkTarget is not null)
            throw new IOException("Provide a regular, existing secret file, not a symbolic link.");
        const UnixFileMode exposed = UnixFileMode.GroupRead | UnixFileMode.GroupWrite |
            UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.OtherWrite | UnixFileMode.OtherExecute;
        if ((File.GetUnixFileMode(path) & exposed) != 0)
            throw new IOException("Secret input files must have permissions 0600 or stricter.");
    }

    [GeneratedRegex(@"^[0-9][A-Za-z0-9.+:~\-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex VersionPattern();
}
