using System.Text.Json;
using ImageFactory;

// Run from the repository root on a workstation or existing CI runner.
var process = new ProcessRunner();
try
{
    switch (args)
    {
        case ["resolve", var release, var location]:
            _ = Policy.UbuntuCodename(release);
            var sku = release == "24.04" ? "cis-ubuntulinux2404-l1-gen2" : "cis-ubuntulinux2204-l1-gen2";
            const string publisher = "center-for-internet-security-inc";
            const string offer = "cis-ubuntu";
            var urn = $"{publisher}:{offer}:{sku}:latest";
            using (var image = JsonDocument.Parse(await process.Run("az",
                ["vm", "image", "show", "--location", location, "--urn", urn, "--output", "json"], true)))
            {
                var root = image.RootElement;
                var version = root.GetProperty("name").GetString()!;
                if (!System.Text.RegularExpressions.Regex.IsMatch(version, @"^\d+\.\d+\.\d+$"))
                    throw new InvalidDataException("Azure did not return an explicit image version.");
                if (root.GetProperty("hyperVGeneration").GetString() != "V2")
                    throw new InvalidDataException("Expected a Gen2 source image.");
                if (root.TryGetProperty("architecture", out var architecture) && architecture.GetString() != "x64")
                    throw new InvalidDataException("Expected an x64 source image.");
                var plan = root.GetProperty("plan");
                if (plan.ValueKind != JsonValueKind.Object)
                    throw new InvalidDataException("CIS Marketplace purchase-plan metadata was not returned.");
                var output = new Dictionary<string, string>
                {
                    ["source_image_sku"] = sku,
                    ["source_image_version"] = version,
                    ["plan_name"] = plan.GetProperty("name").GetString()!,
                    ["plan_product"] = plan.GetProperty("product").GetString()!,
                    ["plan_publisher"] = plan.GetProperty("publisher").GetString()!
                };
                Directory.CreateDirectory("artifacts");
                File.WriteAllText($"artifacts/source-{release}.pkrvars.json", JsonSerializer.Serialize(output, new JsonSerializerOptions { WriteIndented = true }));
                File.WriteAllText($"artifacts/marketplace-{release}.json", root.GetRawText());
                Console.WriteLine($"Resolved {publisher}:{offer}:{sku}:{version}. Review the purchase plan and accept terms before building.");
            }
            break;
        case ["publish"]:
            await process.Run("dotnet", ["publish", "src/ImageProvisioner/ImageProvisioner.csproj", "-c", "Release", "-r", "linux-x64", "--self-contained", "true", "-o", "artifacts/provisioner"]);
            break;
        case ["check", var azureVars, var sourceVars]:
            await Check(azureVars, sourceVars);
            break;
        case ["build", var azureVars, var sourceVars]:
            await Check(azureVars, sourceVars);
            await process.Run("packer", ["build", $"-var-file={azureVars}", $"-var-file={sourceVars}", "packer"], timeoutSeconds: 14400);
            break;
        default:
            Console.WriteLine("Factory resolve <24.04|22.04> <region> | publish | check <azure.pkrvars.hcl> <source.pkrvars.json> | build <azure.pkrvars.hcl> <source.pkrvars.json>");
            return 2;
    }
    return 0;
}
catch (Exception error)
{
    Console.Error.WriteLine(error.Message);
    return 1;
}

async Task Check(string azureVars, string sourceVars)
{
    if (!File.Exists(azureVars) || !File.Exists(sourceVars) || !File.Exists("artifacts/provisioner/ImageProvisioner"))
        throw new FileNotFoundException("Prepare variable files and run Factory publish first.");
    using var source = JsonDocument.Parse(File.ReadAllText(sourceVars));
    var root = source.RootElement;
    var urn = $"{root.GetProperty("plan_publisher").GetString()}:{root.GetProperty("plan_product").GetString()}:{root.GetProperty("source_image_sku").GetString()}:{root.GetProperty("source_image_version").GetString()}";
    using var terms = JsonDocument.Parse(await process.Run("az", ["vm", "image", "terms", "show", "--urn", urn, "-o", "json"], true));
    if (!terms.RootElement.GetProperty("accepted").GetBoolean())
        throw new InvalidOperationException("Marketplace terms have not been accepted in the active subscription. Review and accept them before building.");
    await process.Run("packer", ["init", "packer"]);
    await process.Run("packer", ["validate", $"-var-file={azureVars}", $"-var-file={sourceVars}", "packer"]);
}
