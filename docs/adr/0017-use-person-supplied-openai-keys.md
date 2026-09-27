# Use person-supplied OpenAI keys

The Homebrew beta will ask each person for their own OpenAI API key instead of operating a hosted credential broker. Voice is optional: without a key, Roaming, Park, Hide, and character selection still work, and Summon explains how to add a key.

The key is entered only through an explicit settings action, stored only in the macOS Keychain, never written to preferences, files, or logs, and removable from the Status Menu. A credential service bundled inside the app reads the key and mints short-lived Realtime client secrets through the same allowlisted request the loopback broker makes today. The app process receives only those ephemeral secrets during a Voice Session and still connects directly to OpenAI over WebRTC.

This removes the Node.js runtime from the shipped product and costs the project nothing per conversation. The tradeoff is setup friction: a person needs an OpenAI API account with billing, and they pay for their own Realtime usage. Onboarding must state both plainly, and must repeat that OpenAI processes voice remotely.

This supersedes the requirement in ADR 0015 that an authenticated remote broker precede external distribution. It does not permit embedding a developer-owned or shared key in any build. A hosted broker remains the path for people without an OpenAI account and must keep the same credential Interface so it can replace the Keychain source without changing the Voice Session.
