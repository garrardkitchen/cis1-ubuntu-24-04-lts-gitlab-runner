# CI setup

## GitHub validation

The GitHub workflow runs on pushes to main and pull requests with `contents: read`. It compiles C#, runs the executable tests, publishes the Linux provisioner, validates the Packer template using synthetic values and validates Terraform with no backend. It never performs an Azure plan/apply or image build. No secrets are needed.

## Optional GitLab image build

Mirror/import the repository into GitLab to use `.gitlab-ci.yml`, or adapt it to your existing GitLab pipeline. Hosting the code in GitHub does not run GitLab jobs automatically.

Use an existing dedicated Linux runner tagged `image-factory`, with private routing and the prerequisites listed in the README. The sample runs only on protected refs. Protect the default branch and the image-build runner; do not allow untrusted merge-request code to execute there.

Configure `gitlab_federation` in Terraform with your issuer and the exact project/branch subject, then apply. Use audience `api://AzureADTokenExchange` in both Azure and GitLab. The issuer must be reachable by Entra for OIDC discovery.

Configure these protected GitLab CI variables:

| Variable | Type | Value |
|---|---|---|
| `AZURE_CLIENT_ID` | Variable | Terraform `builder_client_id` output |
| `AZURE_TENANT_ID` | Variable | Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Variable | Subscription ID |
| `AZURE_PACKER_VARS` | File | Reviewed environment Packer variables |
| `CIS_SOURCE_VARS` | File | Reviewed resolved source JSON, with explicit version |

The source is deliberately not re-resolved to `latest` in the build job. The Azure CLI login checks terms; Packer authenticates with the GitLab OIDC token. No client secret is stored. Ensure Marketplace terms were accepted beforehand by an authorised operator and that the selected subscription matches the variables.

Run the manual `build-image` job. It serializes builds against the shared build resource group and publishes only the package inventory and Packer manifest as CI artifacts. It excludes Azure CLI token cache and provisioner binaries from artifacts.

Increase `image_version` for every successful publication. Keep separate environment/source files for 22.04 and 24.04 and separate package pin files when pinning. The pipeline does not deploy candidate VMs or run a CIS scanner yet; complete those release gates before using the image in production.
