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

The script uses a compatible Xcode for this process, creates empty external-contributor
credentials only when absent, and runs the upstream staging simulator build.
It does not select a signing team or change the system-wide developer directory.
Xcode first-launch components and license acceptance must already be completed.
Build output is saved to ignored `artifacts/personal-build.log`.

Swift packages are resolved by Xcode. Ruby/Fastlane are for the release and automation
workflows; they are not needed just to invoke the staging build in the Makefile.

## Status

- Upstream 8.19 cloned; personal branch created.
- Personal product requirements and a proposed Dropbox metadata format recorded.
- Xcode 26.6 Universal installed; Apple package signature verified.
- First upstream build is waiting for the user to accept the Xcode license and finish first launch.
- No Dropbox account connection, device signing, or personal Books functionality yet.

## Library preparation

[docs/personal/dropbox-template/AGENTS.md](docs/personal/dropbox-template/AGENTS.md)
is a proposed instruction file for a future selected Dropbox library folder.
The metadata schema and example are stored beside it. These are templates in the
source repository, not a claim that the Dropbox folder has been created or changed.

Keep real audio, real reading records, OAuth tokens, signing material, and local
credentials out of this source repository.
