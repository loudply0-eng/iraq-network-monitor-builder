# Security Policy

## Supported release

The default branch (`main`) is the source for official production releases. Pull-request builds are validation builds only and must never receive production signing or deployment credentials.

## Reporting a vulnerability

Please do not publish credentials, private keys, personal data, or an exploitable vulnerability in a public issue or pull request.

If GitHub Private Vulnerability Reporting is enabled for this repository, use the repository's **Security** tab to submit a private report. Otherwise, contact the repository owner through GitHub before sharing technical details publicly.

## Secrets and signing material

- Never commit Android keystores, OTA private keys, SSH private keys, passwords, access tokens, or populated environment files.
- Keep production signing and deployment credentials in GitHub Actions secrets; keep only the OTA public verification key in repository variables/source.
- Rotate any credential immediately if it may have been exposed. Removing a secret from the latest commit does not remove it from Git history or make the credential safe again.
- Do not print secret values in workflow logs, artifacts, issue comments, or build output.

## Release integrity

- Official releases must be built from the trusted default branch after source analysis and tests pass.
- Release builds must verify the established Android signing certificate before publishing.
- OTA manifests must be signed with the dedicated Ed25519 key; clients must verify the signature and APK SHA-256 before installation.
- Pull-request workflows must remain unprivileged and must not access production signing or deployment secrets.

## Maintainer checklist

Before merging security-sensitive changes, review workflow permissions, third-party Actions, dependency changes, signing configuration, manifest validation, and server publication behavior. Keep the default branch protected with required pull-request reviews and successful CI checks, and disallow force pushes and branch deletion.
