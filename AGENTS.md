# HeyDay

macOS desktop day-view widget for HEY Calendar. Single SwiftUI file (`Sources/HeyDay.swift`) that shells out to the `hey` CLI (`--json`). Build with `./build.sh`, install with `./build.sh install`.

## Releasing

Releases are built, signed and notarized locally on Yazin's Mac. There's no CI: the signing certificate only lives in this keychain.

1. Commit and `git push` first. The script pushes only the tag.
2. Pick the next version from `gh release list` (semver, `v` prefix), then run:

   ```sh
   PUBLISH=1 VERSION=v0.2.0 ./build.sh release
   ```

   This builds a universal (arm64 + x86_64) app, signs it with "Developer ID Application: Yazin Alirhayim (88M2R3XJZH)" using hardened runtime, notarizes and staples it, checks it with `spctl`, then tags, pushes the tag and runs `gh release create` with `build/HeyDay.zip` and generated notes. Notarization takes about 30–60s. Drop `PUBLISH=1` to stop after the notarized zip.
3. Check that the README download link works: `https://github.com/yazinsai/hey-widget/releases/latest/download/HeyDay.zip`. The asset must stay named `HeyDay.zip`.

Credentials:
- **Signing:** auto-detected from the keychain (`security find-identity -v -p codesigning`). Override with `SIGN_ID`.
- **Notarization:** keychain profile `heyday-notary`. It wraps App Store Connect API key `CVJ23CD7P5`; the key file is `~/ai/projects/pray.bh/fastlane/AuthKey_CVJ23CD7P5.p8` and the issuer ID is `ASC_ISSUER_ID` in `~/ai/projects/pray.bh/fastlane/.env`. If the profile is missing, recreate it:

  ```sh
  source ~/ai/projects/pray.bh/fastlane/.env
  xcrun notarytool store-credentials heyday-notary --key ~/ai/projects/pray.bh/fastlane/AuthKey_CVJ23CD7P5.p8 --key-id CVJ23CD7P5 --issuer "$ASC_ISSUER_ID"
  ```

  CI alternative: set `NOTARY_KEY`, `NOTARY_KEY_ID` and `NOTARY_ISSUER` instead of using the profile.
- **Notarization failures:** run `xcrun notarytool log <submission-id> --keychain-profile heyday-notary`. A common cause is code added that needs an entitlement under hardened runtime.

Never commit `.p8` keys, issuer IDs or certificates.

## Agent skills

### Issue tracker

Issues live as local markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
