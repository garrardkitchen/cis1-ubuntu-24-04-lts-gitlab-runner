# Release checks and maintenance

## Before the first build

Confirm the selected CIS SKU and purchase plan in the target region. The default is Level 1, Gen2, x64. Trusted Launch support is not inferred from Gen2 and is not enabled by this scaffold; adopt it only after validating the source, destination definition and workload requirements together.

The Packer host must reach the private build VM over SSH. Keep SSH and passwordless build-user sudo available during provisioning. The template reads temporary scripts with `/bin/sh` and reads the provisioning scripts with `/bin/bash` from `/opt/image-factory`; it does not remount `/tmp` or remove CIS `noexec` controls. A CIS configuration that blocks this build path needs a specific reviewed adjustment, followed by reassessment.

The build subnet needs DNS, Ubuntu repositories and HTTPS access to Docker, GitLab package delivery, Datadog keys/APT and Microsoft packages, including vendor redirects/CDNs. Production VMs also need their vendor service endpoints and GitLab/container registry. Use the official endpoint lists, not only the root package hostnames.

## What the build verifies

The installer checks supported OS/architecture, APT package installation, Docker daemon connectivity, Compose/Buildx and CLI availability. It exports an inventory and refuses an already enrolled source. Vendor agents stay disabled until per-VM configuration.

The original CIS assessment describes the source image. This derived image is **not automatically CIS-certified or compliant**. Installing Docker changes networking and adds privileged capabilities. The repository does not bundle a licensed CIS scanner or invent a passing assessment.

## Required candidate-VM checks

1. Deploy from the exact gallery version and confirm its OS/release and unique hostname/machine ID. Reboot and verify clean cloud-init provisioning and Azure Linux Agent health.
2. Re-run the applicable CIS Level 1 benchmark with your approved tooling. Record accepted exceptions and retain the assessment outside this public repository. Scan package vulnerabilities.
3. Confirm Docker daemon startup, DNS, registry authentication and an approved test-container run. Validate Compose with your intended workload.
4. Enrol Datadog, Runner and Defender. Confirm telemetry in both vendor portals and a real GitLab job, including clone and artifact upload.
5. Validate host and container network isolation. Docker's packet-filter rules can interact with host firewall policy; test actual traffic paths. Do not broadly disable firewall controls to make a build pass.
6. Confirm workload CPU/memory/disk and Defender performance. Add only reviewed exclusions; no blanket exclusions for Docker storage or runner workspaces are shipped.
7. Promote an explicit version through environments. Candidates are excluded from `latest`; release selection is intentionally manual until gates are automated.

## Identity and secrets

Terraform creates a managed identity with optional GitLab OIDC trust. The identity has Contributor only in the dedicated build resource group, a custom image-version publisher role in the gallery group, VNet read and join rights on the selected subnet. It cannot assign Azure roles or accept Marketplace terms using those grants. Terraform provisioning requires a more privileged operator.

Do not grant untrusted jobs access to the image-build runner or identity. Docker daemon access is effectively root-equivalent. The job executor defaults to non-privileged containers and does not receive the host socket. Each deployed VM must register separately; never capture runner tokens, system IDs or host-specific Datadog configuration in a new base.

## Patching and repeatability

Rebuild for source and application package updates. Resolve a new source explicitly, review it, build, assess and promote. Updating a gallery image does not patch already deployed VMs; roll them forward or use your existing in-place patching process.

Package pins and recorded inventory improve traceability but are not a full repository snapshot. Keep package mirrors/snapshots if deterministic long-term rebuilds are required. `apt upgrade` retains existing configuration files; review newly introduced package defaults and pending reboot effects on a candidate VM.

Use `git diff` to review provider lockfile and dependency updates. The gallery uses AVM `0.2.1`; AzureRM starts at the verified `5.4.x` release line. Actions are pinned by commit SHA. Packer's Azure plugin is pinned to `2.6.0`; review upgrades deliberately.

## Sources

- [CIS Azure images](https://www.cisecurity.org/cis-hardened-images/microsoft)
- [Packer Azure builder](https://developer.hashicorp.com/packer/integrations/hashicorp/azure/latest/components/builder/arm)
- [Azure gallery purchase plans](https://learn.microsoft.com/en-us/azure/virtual-machines/marketplace-images)
- [Docker Ubuntu installation and firewall considerations](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Compose plugin](https://docs.docker.com/compose/install/linux/)
- [GitLab Runner packages and helper versions](https://docs.gitlab.com/runner/install/linux-repository/)
- [AVM Compute Gallery](https://registry.terraform.io/modules/Azure/avm-res-compute-gallery/azurerm/latest)
