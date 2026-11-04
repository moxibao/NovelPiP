# NovelPiP — unsigned IPA build

This repository is a source-code prototype for an iOS TXT reader with native Picture in Picture support.

## Build an unsigned IPA from Windows

1. Create a GitHub repository and upload the contents of this ZIP.
2. Open the repository's **Actions** tab.
3. Select **Build NovelPiP Unsigned IPA**.
4. Choose **Run workflow**.
5. When the run completes, download the `NovelPiP-unsigned-IPA` artifact.
6. Extract the downloaded artifact ZIP. It contains `NovelPiP-unsigned.ipa`.
7. Sign that IPA with your own sideloading tool.

The workflow builds on a GitHub-hosted macOS runner. It does not sign the app.

## Important testing note

This is an early source prototype, not a verified release. The workflow may expose compile-time issues that need fixing. Even after a successful build, test PiP behavior on your iPhone: the sample-buffer PiP implementation and the system skip controls can behave differently across iOS versions. The app currently focuses on TXT import and basic pagination; EPUB/PDF and production-grade layout are not included yet.
