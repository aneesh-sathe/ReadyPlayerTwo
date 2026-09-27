# Distribute through a Homebrew tap

V1 will reach people as a prebuilt app installed with `brew install --cask aneesh-sathe/tap/readyplayertwo` from the personal tap `aneesh-sathe/homebrew-tap`. It will not be submitted to the App Store, and people will not need Xcode, Node.js, a clone of this repository, or a terminal launcher to use it. `./scripts/run` remains the development launch seam.

The official `homebrew/cask` repository is not the initial channel because a self-submitted cask needs at least 90 forks, 90 watchers, or 225 stars, and every cask there must pass Homebrew's Gatekeeper checks. A personal tap has neither requirement, so it is the fastest path to real users. The cask will move to `homebrew/cask` once the project is notable and notarized.

The first public beta is ad hoc signed. Homebrew no longer supports `--no-quarantine`, so macOS blocks the first launch until the person chooses Open Anyway in System Settings. The cask caveats must explain that step, and it must not strip the quarantine attribute on the person's behalf. Ad hoc signatures change on every release, so microphone consent and Keychain access prompts may repeat after each upgrade. Developer ID signing and notarization will replace ad hoc signing as soon as Apple Developer Program enrollment is complete.

Each release is a versioned GitHub Release asset built by CI from a tag. Homebrew owns upgrades through `brew upgrade --cask`, so the app does not ship its own updater. This supersedes the distribution limits in ADR 0013 and the PRD's exclusion of public distribution, launch at login, and notarization. The rest of the V1 product boundary is unchanged.
