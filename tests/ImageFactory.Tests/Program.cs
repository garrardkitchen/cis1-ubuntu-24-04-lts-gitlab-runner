using System.IO.Compression;
using ImageFactory;

// Dependency-free executable tests. A failed assertion returns a nonzero exit.
var count = 0;
Check(Policy.UbuntuCodename("24.04") == "noble", "24.04 mapping");
Check(Policy.UbuntuCodename("22.04") == "jammy", "22.04 mapping");
Throws(() => Policy.UbuntuCodename("20.04"), "unsupported release");
Policy.ValidatePins(new Dictionary<string, string>());
Policy.ValidatePins(new Dictionary<string, string> { ["docker-ce"] = "5:28.0.0-1~ubuntu.24.04~noble" });
Throws(() => Policy.ValidatePins(new Dictionary<string, string> { ["docker-ce"] = "1; touch /tmp/unwanted" }), "version injection");
Throws(() => Policy.ValidatePins(new Dictionary<string, string> { ["unapproved-package"] = "1.0" }), "unknown package");
Throws(() => Policy.ValidatePins(new Dictionary<string, string> { ["gitlab-runner"] = "1.0" }), "missing matching helper");
Throws(() => Policy.ValidatePins(new Dictionary<string, string> { ["gitlab-runner"] = "1.0", ["gitlab-runner-helper-images"] = "2.0" }), "mismatched helper");
Policy.ValidatePins(new Dictionary<string, string> { ["gitlab-runner"] = "1.0", ["gitlab-runner-helper-images"] = "1.0" });

WithZip([Policy.LinuxOnboardingScript], zip => Check(Policy.SelectLinuxScript(zip).Name == Policy.LinuxOnboardingScript, "Linux ZIP accepted regardless of outer filename"));
WithZip(["WindowsDefenderATPLocalOnboardingScript.cmd"], zip => Throws(() => Policy.SelectLinuxScript(zip), "Windows-only ZIP rejected"));
WithZip(["../" + Policy.LinuxOnboardingScript], zip => Throws(() => Policy.SelectLinuxScript(zip), "path traversal rejected"));
WithZip([Policy.LinuxOnboardingScript, "nested/" + Policy.LinuxOnboardingScript], zip => Throws(() => Policy.SelectLinuxScript(zip), "duplicate scripts rejected"));

if (OperatingSystem.IsLinux())
{
    var temp = Path.GetTempFileName();
    try
    {
        File.SetUnixFileMode(temp, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        Policy.RequirePrivateFile(temp);
        File.SetUnixFileMode(temp, UnixFileMode.UserRead | UnixFileMode.OtherRead);
        Throws(() => Policy.RequirePrivateFile(temp), "public secret input rejected");
        var literal = "$(touch /tmp/not-executed); `id` spaces";
        var output = await new ProcessRunner().Run("/usr/bin/printf", ["%s", literal], true);
        Check(output == literal, "process arguments are literal, not shell code");
        try
        {
            await new ProcessRunner().Run("/usr/bin/false", [], true);
            throw new Exception("Nonzero exit was accepted.");
        }
        catch (InvalidOperationException) { count++; }
    }
    finally { File.Delete(temp); }
}
Console.WriteLine($"PASS: {count} assertions.");

void Check(bool condition, string name)
{
    if (!condition) throw new Exception($"FAIL: {name}");
    count++;
}
void Throws(Action action, string name)
{
    try { action(); }
    catch (Exception e) when (e is ArgumentException or InvalidDataException or IOException)
    { count++; return; }
    throw new Exception($"FAIL: {name}");
}
static void WithZip(string[] names, Action<ZipArchive> action)
{
    using var buffer = new MemoryStream();
    using (var archive = new ZipArchive(buffer, ZipArchiveMode.Create, leaveOpen: true))
        foreach (var name in names)
        {
            using var writer = new StreamWriter(archive.CreateEntry(name).Open());
            writer.Write("# test fixture, not an onboarding script");
        }
    buffer.Position = 0;
    using var reader = new ZipArchive(buffer, ZipArchiveMode.Read);
    action(reader);
}
