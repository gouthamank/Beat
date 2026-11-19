# Releasing

For the maintainer. Pushing a version tag drafts a GitHub Release with a signed `Beat.dmg`
(`.github/workflows/release.yml`). The DMG is built by `make mac-release` (needs `brew install create-dmg`), which also
runs locally to try one first.

Released builds keep the bundle ID `dev.gouthaman.Beat`: the workflow writes `BEAT_BUNDLE_PREFIX = dev.gouthaman` into
its own `Config/Secrets.xcconfig`, so settings and Keychain entries carry over from one release to the next.

## Once

Add these repository secrets (**Settings ▸ Secrets and variables ▸ Actions**):

1. In Keychain Access, under **My Certificates**, right-click **Beat Local Signing ▸ Export**, save it as a `.p12`
   with a password, then `base64 -i Beat.p12 | gh secret set MAC_CERTIFICATE_P12`,
   `gh secret set MAC_CERTIFICATE_PASSWORD` (it asks for the password) and delete the `.p12`. The certificate is the
   self-signed one from README > Building > On the Mac.
2. Optional, for scrobbling in released builds: `gh secret set LASTFM_API_KEY` and `gh secret set LASTFM_SHARED_SECRET`.
   These end up readable inside the downloaded app, as in any desktop Last.fm client.

## Each release

1. Raise `CFBundleShortVersionString` in `project.yml` (both targets) and commit.
2. `git tag v1.4.0 && git push origin v1.4.0`. The workflow stops if the tag doesn't match the version.
3. When it finishes, check the draft on GitHub's Releases page and publish it.
