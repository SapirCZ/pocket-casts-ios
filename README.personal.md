# Personal Books fork

This branch starts from upstream Pocket Casts **8.19** (commit `4a907d631f527f602e14fb7c5cc578449f4df938`).
Its pinned Xcode is **26.6**, with an iOS deployment target of **17.0**.

The work is for a personal iOS build with a Dropbox audiobook library, offline listening,
bookmarks, bedtime anchors, and a reading journal. The agreed product plan is in
[docs/personal/PLAN.md](docs/personal/PLAN.md).

## First build

Install **Xcode 26.6 Universal** from Apple's developer downloads. Universal is the
distribution for an Intel Mac; the Apple silicon-only archive is unsuitable here.

Complete the Xcode first launch in Terminal (review and accept the license yourself):

```sh
open scripts/personal/xcode-first-launch.command
```

Then run:

```sh
bash scripts/personal/bootstrap.sh
```

The original staging scheme embeds an Apple Watch app, so it requires both iOS
26.5 and watchOS 26.5 simulator runtimes. Install their Universal variants from
Terminal when missing, then rerun the bootstrap script:

```sh
env DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer \
  xcodebuild -downloadPlatform iOS -buildVersion 26.5 -architectureVariant universal
env DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer \
  xcodebuild -downloadPlatform watchOS -buildVersion 26.5 -architectureVariant universal
```

The simulator SDK appearing in `xcodebuild -showsdks` is not sufficient evidence
that the runtime needed by the build destination is installed.

The script uses a compatible Xcode for this process, creates empty external-contributor
credentials only when absent, and runs the upstream staging simulator build.
It does not select a signing team or change the system-wide developer directory.
Xcode first-launch components and license acceptance must already be completed.
Build output is saved to ignored `artifacts/personal-build.log`.

Swift packages are resolved by Xcode. Ruby/Fastlane are for the release and automation
workflows; they are not needed just to invoke the staging build in the Makefile.
Build-tool plugin commands use `--disable-keychain --disable-netrc` for public packages
and release artifacts, avoiding repeated prompts to read saved GitHub credentials.
This is local to those commands and does not change the Mac's Keychain settings.

## Status

- Upstream 8.19 cloned; personal branch created.
- Personal product requirements and a proposed Dropbox metadata format recorded.
- Xcode 26.6 Universal installed; Apple package signature verified.
- Xcode license and first launch verified; source package dependencies resolved.
- iOS 26.5 and watchOS 26.5 Universal runtimes installed.
- Language and theme resource generation verified on the Intel Mac.
- `make build_staging` succeeded on the Intel Mac; the simulator app contains x86_64 and arm64 slices.
- Installed and launched on an iPhone 17 Pro simulator running iOS 26.5. The process
  remained alive more than 13 minutes after launch.
- Visual inspection passed: the Pocket Casts welcome screen rendered on the simulator.
- The Dropbox source folder has been confirmed by the owner. Its path and identifiers
  are kept in ignored local setup artifacts rather than this public repository.
- A dedicated Dropbox developer app was created with the owner's explicit account
  choice and API-terms consent. Read scopes and the native callback URI have been
  configured with separate owner approval. No developer-console token or client secret is used.
- Books replaces Discover in the tab bar. Podcast search remains in Podcasts, and
  Discover deep links open within that tab's navigation stack.
- Books implements native Dropbox PKCE sign-in, folder browsing, download progress,
  cancellation, and a list of local books usable without Dropbox credentials.
- Downloads are streamed to a temporary file on disk. Before queue insertion, the
  app verifies the pinned revision, byte count, Dropbox content hash, playable audio
  track, and finite positive duration. MP4 containers must actually contain audio.
- A separate `PersonalBook` table preserves identity and playback progress after
  audio/UserEpisode deletion. Repeated selection reuses the same local episode.
- 105 selected tests passed on the iOS 26.5 Intel simulator: catalog, OAuth,
  MP3/M4B import, file integrity, retry/cancellation, book persistence, and existing
  playback queue/user-file persistence regressions. The UnitTests plan now points
  to the current consolidated `Modules` package so module tests actually run.
  Visual checks confirmed the Books tab, Discover navigation from Podcasts, and
  Hebrew podcast search results for “שיר אחד”.
- Native sign-in, root/nested folder browsing, and a live MP3 download from the
  shared Dropbox library were verified in the simulator. The verified audio appears
  under On this device, with exactly one imported episode and one Up Next row.
- The content-download request pins revisions using `path: "rev:…"`; Dropbox rejects
  the retired separate `rev` argument. All 12 focused request/import/catalog tests
  passed after this correction.
- A separate phone-only personal project passed signed arm64 device builds and
  was installed as Sapir Books on an iPhone 15 Plus running iOS 26.6.1, including
  the local Books configuration. The bundle passed deep/strict signature verification.
  First launch still requires checking the phone's developer trust; native Dropbox
  authorization and live download/queue verification on the phone remain pending.
- Personal bookmarks, bedtime anchors, and journal/export features remain pending.

## Local Books configuration

Run `python3 scripts/personal/configure-books.py` before opening/building in Xcode.
The bootstrap script also runs it. It reads the ignored `artifacts/dropbox-app.json`
and `artifacts/library-source.json` and generates ignored
`podcasts/Main/Books/BooksLocalConfiguration.json`, bundled into this personal build.
The configuration contains the public client ID and the selected library identifiers,
never tokens or an app secret. Without local configuration, Books shows a setup state.

Register `db-<clientID>://oauth` as the exact Dropbox redirect URI. Enable public
clients and read scopes `account_info.read`, `files.metadata.read`, `files.content.read`.
The native session uses S256 PKCE, a random state, exact callback checks, and short-lived
access tokens with refresh tokens in this device's Keychain. Disconnecting removes
local credentials and keeps downloaded books.

In this version, keep Books open until downloading/validation finishes. An interrupted
download can be retried; partial or invalid files do not enter Up Next. A verified file
moved into place before a crash can be recovered on the next selection. The source
revision is pinned to protect playback positions when Dropbox audio is replaced.

Books use the existing local player and queue, with automatic Pocket Casts uploads and
file metadata sync blocked. While the queue contains personal books, its Pocket Casts
cloud queue sync is paused so remote changes cannot remove local books. Normal podcast
queue sync resumes when no personal books remain queued. This does not affect playback.

## Library preparation

[docs/personal/dropbox-template/AGENTS.md](docs/personal/dropbox-template/AGENTS.md)
is a proposed instruction file for the selected Dropbox library folder.
The metadata schema and example are stored beside it. These are templates in the
source repository, not a claim that the Dropbox folder has been created or changed.

Keep real audio, real reading records, OAuth tokens, signing material, and local
credentials out of this source repository.

The selected folder contains both loose MP3/M4B files and nested series/book folders.
Browse direct children on demand, keep folders navigable, and hide dot-prefixed
technical entries and non-audio files. Do not treat each series folder as one book.
An MP4 extension is only a candidate: validate that the actual file has playable audio
before importing it. Existing files have not been moved or renamed.

The native app needs its own Dropbox app registration and OAuth authorization;
the connected chat tool does not provide credentials for an iOS app. The existing
shared library requires **Full Dropbox** content access with read-only scopes
`files.metadata.read` and `files.content.read`, rather than an isolated App Folder.
Use PKCE and store refresh credentials in Keychain. Keep backup writes separate
from the source-library connection until their destination is agreed.
See Dropbox's [OAuth guide](https://docs.dropboxapi.com/dropbox-api/docs/oauth) and
[folder listing reference](https://docs.dropboxapi.com/dropbox-api/api-reference/user-endpoints/files/list-folder-continue).

To rerun the catalog tests on an installed simulator:

```sh
env DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer \
  make test_staging ONLY_TESTING=PocketCastsTests/DropboxLibraryClientTests
```

Use `PocketCastsTests/BooksImportTests`, `PocketCastsTests/DropboxOAuthTests`, or
`PocketCastsDataModelTests/PersonalBookTests` in `ONLY_TESTING` for the other Books checks.

## Personal iPhone build

Generate a local phone project with your Apple development team ID:

```sh
python3 scripts/personal/configure-device.py --team YOURTEAMID
```

The ignored `.personal-device.xcodeproj` uses the same app sources, with a separate
bundle identifier (`com.sapircz.pocketcasts.books`) and display name, **Sapir Books**.
It keeps credential/localization generation, and omits Watch, extensions, and the
upstream restricted entitlements for basic Personal Team testing. The original
project and the installed Pocket Casts app remain separate. `--bundle-id` can
override the personal identifier. Generated signing configuration stays local.

The `Sapir Books` scheme uses StagingDebug. Connect and unlock the iPhone, then
build it using Xcode with your Personal Team. First-time automatic signing needs
Apple to register the device and create a development provisioning profile.
Native Dropbox authorization must also be completed on the phone; simulator
credentials are not copied.

Keep enough disk space for device compilation. Xcode may copy a large optional
system-symbol cache when opening the phone in its GUI; it is not the app download.
