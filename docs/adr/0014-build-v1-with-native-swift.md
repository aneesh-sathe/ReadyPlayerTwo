# Build v1 with native Swift

V1 will use Swift 6, AppKit, and SpriteKit in a locally signed macOS app bundle. A thin Xcode app shell will own packaging, lifecycle, microphone consent, and end-to-end tests, while internal Modules use Swift Package Manager. SwiftUI is limited to compact settings UI.

Native Swift accepts macOS platform dependence in exchange for direct control over the Status Menu, transparent non-activating panels, display geometry, Spaces, click-through input, SpriteKit rendering, and audio lifecycle. A web or cross-platform shell would make the defining desktop behavior less predictable without improving the v1 product boundary.

`CompanionRuntime` will be the high behavioral Seam. AppKit, SpriteKit, OpenAI Realtime, the credential broker, system events, clock, and randomness will remain behind injected ports with production and test Adapters.
