# Use ephemeral Realtime credentials

The standard OpenAI API key will never enter the macOS app bundle or process. During v1 development, a terminal-supervised Node.js broker bound to loopback will read the standard key from the environment, mint a short-lived Realtime client secret, and return only that secret to the app. The launcher must explicitly remove the standard key from the app process environment. The app will then connect directly to OpenAI over WebRTC, so the broker never proxies conversation audio.

The broker Interface will remain location-independent. Before distributing the app to external testers, the same contract must move to an authenticated remote deployment. Embedding a shared standard key or a reusable broker credential in a distributed client is prohibited.

Superseded in part by ADR 0017: the Homebrew beta mints secrets from a person-supplied key in the Keychain instead of requiring a remote broker first.
