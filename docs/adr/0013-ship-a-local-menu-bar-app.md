# Ship a local menu bar app

V1 will be a locally built macOS app bundle that does not require App Store publication. It will run as a Dockless agent app with a persistent Status Menu, no conventional main window, and a terminal command for development builds and launch. The Status Menu will expose Summon or End Conversation, Roam, Park, Hide or Show, avatar selection, voice settings, and Quit.

The development launch command supervises the local credential broker and app until Quit or a terminal interrupt. Either exit path must stop the Voice Session, microphone, windows, app, and broker without leaving an orphaned process. The Status Menu persists while the app is running, including while the Companion is Parked or Hidden.

This accepts native platform dependence in exchange for correct macOS lifecycle, microphone permission, global shortcut, transparent window, menu bar, audio, Spaces, and input behavior. App Store packaging, public distribution, automatic updates, and launch at login remain outside v1.

Superseded in part by ADR 0016: V1 is publicly distributed through a Homebrew tap, and launch at login is in scope.
