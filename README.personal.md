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
- Books replaces Discover in the tab bar. Podcast search remains in Podcasts, and
  Discover deep links open within that tab's navigation stack.
- The first Books screen explains the library and shows its pending connection state.
  A read-only Dropbox listing client handles folders, audio candidates, pagination,
  and shared-folder namespaces; OAuth is not connected yet.
- Six focused `DropboxLibraryClientTests` passed on the iOS 26.5 Intel simulator.
  Visual checks confirmed the Books tab, Discover navigation from Podcasts, and
  Hebrew podcast search results for “שיר אחד”.
- Device signing, audio downloads, book records, bookmarks, and journal features are pending.

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
