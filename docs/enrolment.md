# Configure each deployed VM

Keep the VM isolated until all required services are enrolled and healthy. Run these steps on a VM created from the gallery image, never during Packer capture.

Deliver inputs using your approved secret-management path, such as a deployment identity retrieving Key Vault secrets. Store temporary files under a root-owned directory on `/run` with mode `0700`, and make individual files mode `0600`. The C# commands refuse group/world-readable input files and symbolic links. Remove temporary inputs after successful setup; do not commit them or log their contents.

The current repository supplies commands for enrolment. It does **not** yet provide a Key Vault fetcher, VM deployment module or automated first-boot service.

## Defender for Endpoint

From the Defender portal select **Settings > Endpoints > Device management > Onboarding > Linux Server > Local Script**. A ZIP with `WindowsDefender` in its filename can be correct. The contents must include exactly one `MicrosoftDefenderATPOnboardingLinuxServer.py`.

The proposed `GatewayWindowsDefenderATPOnboardingPackage.zip` has not yet been provided or inspected. A Windows-only or gateway-specific package without the Linux script will be rejected. The helper reads only that entry into a private directory and executes Microsoft's script unchanged using Python 3. Python is a vendor prerequisite; our provisioning implementation remains C#.

Run `sudo /opt/image-factory/ImageProvisioner onboard-mde /run/image-secrets/defender.zip`.

The command enables Defender, runs onboarding, restarts it and checks for an organisation identifier. After definition downloads complete, check `mdatp health --field healthy`, `mdatp health --field definitions_status`, and `mdatp health --field real_time_protection_enabled`; confirm the device in your Defender portal. Successful script execution alone is not the release gate. Apply your approved Defender policy and confirm the required licensing and outbound connectivity.

## Datadog

Create a private JSON input with `ApiKey` and `Site`. This C# example shows the schema using an already securely obtained key; it is not a secret-fetch implementation:

```csharp
var settings = new { ApiKey = apiKeyFromYourSecretProvider, Site = "datadoghq.eu" };
```

Run `sudo /opt/image-factory/ImageProvisioner configure-datadog /run/image-secrets/datadog.json`.

It writes a root-owned, `dd-agent`-readable config and starts the agent. Confirm `datadog-agent status` and host arrival in the correct Datadog site. This enables normal host monitoring; Docker socket access, container collection, APM and security monitoring need separate reviewed configuration.

## GitLab Runner

Create the runner in GitLab first. Set server-side project/group scope, protected status, tags and untagged-job policy. Obtain its **runner authentication token** (`glrt-`), not a legacy registration token.

The private JSON input contains `Url`, `AuthenticationToken`, `DockerImage` and `Name`:

```csharp
var settings = new
{
    Url = "https://gitlab.example.com",
    AuthenticationToken = runnerTokenFromYourSecretProvider,
    DockerImage = approvedImageWithSha256Digest,
    Name = Environment.MachineName
};
```

Run `sudo /opt/image-factory/ImageProvisioner register-runner /run/image-secrets/runner.json`.

The helper passes credentials through the child process environment and suppresses registration output. It configures the Docker executor without privileged mode or a host Docker-socket mount inside job containers, then checks registration. It refuses duplicate registration and requires the default job image to be pinned by digest.

Run a real GitLab job with the intended tags. Registration verification does not prove container execution, source cloning, cache access, DNS or artifact upload. This image does not configure Docker-in-Docker; jobs needing to build container images require an explicit build strategy.

## Vendor references

- [Microsoft Linux installation and onboarding](https://learn.microsoft.com/en-us/defender-endpoint/linux-install-manually)
- [Microsoft Linux golden-image support](https://learn.microsoft.com/en-us/defender-endpoint/linux-deploy-defender-for-endpoint-using-golden-images)
- [Datadog Linux Agent](https://docs.datadoghq.com/agent/supported_platforms/linux/)
- [GitLab runner registration](https://docs.gitlab.com/runner/register/)
