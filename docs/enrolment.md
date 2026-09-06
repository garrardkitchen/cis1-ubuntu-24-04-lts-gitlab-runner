# Configure each deployed VM

Keep the VM isolated until required services are enrolled and healthy. These steps run on a deployed VM, never during image capture.

Deliver inputs through your approved secret-management path, such as a deployment identity retrieving Key Vault secrets. Use a root-owned directory under `/run` with mode `0700` and input files mode `0600`. The helpers reject symlinks, other owners and group/world access. Do not enable shell tracing. Remove temporary inputs after successful setup. This repository does not supply a Key Vault fetcher, VM deployment module or first-boot service.

## Defender for Endpoint

Download **Linux Server / Local Script** from Settings > Endpoints > Device management > Onboarding in the Defender portal. The ZIP must contain exactly one `MicrosoftDefenderATPOnboardingLinuxServer.py` at its root. The proposed `GatewayWindowsDefenderATPOnboardingPackage.zip` has not been provided or inspected; its filename alone cannot establish compatibility.

Run `sudo bash /opt/image-factory/enrol.sh defender /run/image-secrets/defender.zip`.

The helper streams only the selected script into a private directory, limits its size, runs Microsoft's script unchanged with Python 3, and removes the temporary copy. Python is used only for the vendor's onboarding script. Windows-only, nested or duplicate script entries are rejected.

After definitions download, check `mdatp health --field healthy`, `mdatp health --field definitions_status` and `mdatp health --field real_time_protection_enabled`. Confirm portal arrival and apply your approved policy. A returned organisation ID alone does not prove protection.

## Datadog

Supply a private JSON object with string fields `ApiKey` (your 32-character API key) and `Site` (for example, `datadoghq.eu`). Run `sudo bash /opt/image-factory/enrol.sh datadog /run/image-secrets/datadog.json`.

The helper writes a root-owned, group-readable `dd-agent` config and restarts the service. Confirm `datadog-agent status` and host arrival. Docker collection, APM and security monitoring require separate reviewed configuration.

## GitLab Runner

Create the runner in GitLab first; set its scope, protected status, tags and untagged-job policy. Use a `glrt-` runner authentication token.

Supply a private JSON object with these string fields:

| Field | Value |
|---|---|
| `Url` | HTTPS GitLab URL without credentials, query or fragment |
| `AuthenticationToken` | Runner authentication token |
| `DockerImage` | Approved image reference ending in `@sha256:` and its 64-character digest |
| `Name` | Unique VM name, using letters, numbers, dot, underscore or hyphen |

Run `sudo bash /opt/image-factory/enrol.sh runner /run/image-secrets/runner.json`.

Credentials pass through the child environment, not command arguments, and registration output is suppressed. The helper refuses duplicate registration, uses the Docker executor without privileged mode or a host socket mount in job containers, and verifies registration. Run a real smoke-test job covering clone, registry, DNS, cache and artifact upload. Container image builds require an explicit build strategy; Docker-in-Docker is not configured.

## References

- [Microsoft Linux onboarding](https://learn.microsoft.com/en-us/defender-endpoint/linux-install-manually)
- [Datadog Linux Agent](https://docs.datadoghq.com/agent/supported_platforms/linux/)
- [GitLab registration](https://docs.gitlab.com/runner/register/)
