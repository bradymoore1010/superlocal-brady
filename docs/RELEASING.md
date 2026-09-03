# Releasing Mail

## Release checklist

- Confirm `CHANGELOG.md`, `AppResources/Info.plist`, and the intended tag agree.
- Run `./scripts/test.sh` and `./scripts/build-app.sh`.
- Run the relevant launch, interaction, and soak checks for any hot-path change.
- Run the repository privacy scan and inspect every staged binary or image.
- Render and review `MailHero`, `MailSocial`, and `MailLaunch` when public visuals changed.
- Create an annotated semantic-version tag and push it to `main`.

## Package locally

```bash
./scripts/package-release.sh v1.0.0
```

The script verifies the ad-hoc signature and writes the app archive plus SHA-256 checksum to the ignored `release/` directory.

## Automated release

Pushing a `v*` tag runs `.github/workflows/release.yml`. The workflow tests and builds on macOS, packages the app, and creates a GitHub Release containing:

- `Mail-macOS-<tag>.zip`
- `Mail-macOS-<tag>.zip.sha256`
- `mail-launch.mp4`

The current archive is ad-hoc signed and not notarized. A future Developer ID release should replace the signing step, submit the archive to Apple's notary service, staple the ticket, and verify Gatekeeper before publishing.
