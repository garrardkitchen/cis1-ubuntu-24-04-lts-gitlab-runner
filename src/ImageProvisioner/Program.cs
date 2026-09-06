using System.Runtime.InteropServices;
using ImageFactory;

if (args.Length == 0)
{
    Console.WriteLine("ImageProvisioner install <pins.json> | verify | seal | onboard-mde <zip> | configure-datadog <json> | register-runner <json>");
    return 2;
}
try
{
    if (!OperatingSystem.IsLinux() || Native.GetEffectiveUserId() != 0)
        throw new InvalidOperationException("Run as root on the target Ubuntu VM.");
    var installer = new Installer(new ProcessRunner());
    switch (args)
    {
        case ["install", var pins]: await installer.Install(pins); break;
        case ["verify"]: await installer.Verify(); break;
        case ["seal"]: await installer.Seal(); break;
        case ["onboard-mde", var zip]: await new Enrollment(new ProcessRunner()).Defender(zip); break;
        case ["configure-datadog", var config]: await new Enrollment(new ProcessRunner()).Datadog(config); break;
        case ["register-runner", var config]: await new Enrollment(new ProcessRunner()).Runner(config); break;
        default: throw new ArgumentException("Unknown command or incorrect argument count.");
    }
    return 0;
}
catch (Exception error)
{
    Console.Error.WriteLine(error.Message);
    return 1;
}

internal static partial class Native
{
    [DllImport("libc", EntryPoint = "geteuid")]
    internal static extern uint GetEffectiveUserId();
}
