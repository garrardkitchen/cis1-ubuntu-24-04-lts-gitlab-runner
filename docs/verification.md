# Verification status

The Bash refactor removes the C# projects, compiled provisioner and .NET SDK requirement. It preserves Terraform infrastructure, Packer image builds and post-deployment enrolment.

Local checks cover Bash syntax, security/input tests, JSON/YAML structure and tracked-file hygiene. GitHub Actions runs the same tests plus ShellCheck, Packer validation and Terraform validation/format checks. Consult the Actions result for this branch; the previous main-branch C# results do not validate these scripts.

The Terraform federation resource uses AzureRM 5.x `user_assigned_identity_id`; the earlier `parent_id` and `resource_group_name` arguments were invalid with that provider.

No Azure image build or vendor enrolment has been run. Still required:

- Resolve a regional CIS source and confirm Marketplace terms.
- Apply Terraform and test RBAC/private networking with Packer.
- Build each OS variant that will be used.
- Boot/reboot a candidate and complete a CIS assessment.
- Inspect the Defender Linux package, enrol the three agents and run a GitLab job.

Passing script/template checks does not establish image compliance or operational readiness.
