import AppKit
import Foundation
import Testing
@testable import ReadyPlayerTwo

@Suite(.serialized)
struct ApplicationPrivacyContractTests {
  @Test
  @MainActor
  func packagedInfoPlistIsDocklessAndRequestsNoLaunchPermission() throws {
    let bundle = Bundle(for: AppDelegate.self)

    #expect(bundle.bundleIdentifier == "com.aneeshsathe.readyplayertwo")
    #expect(bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true)
    #expect(
      bundle.object(forInfoDictionaryKey: "LSMultipleInstancesProhibited")
        as? Bool
        == true
    )
    #expect(
      bundle.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription")
        as? String
        == "ReadyPlayerTwo uses your microphone only during a conversation you explicitly start."
    )

    #expect(
      bundle.object(forInfoDictionaryKey: "NSCameraUsageDescription") == nil
    )
    #expect(
      bundle.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription")
        == nil
    )
    #expect(
      bundle.object(forInfoDictionaryKey: "NSScreenCaptureUsageDescription")
        == nil
    )

    let transportSecurity =
      bundle.object(forInfoDictionaryKey: "NSAppTransportSecurity")
      as? [String: Any]
    #expect(transportSecurity?["NSAllowsArbitraryLoads"] == nil)
    #expect(transportSecurity?["NSAllowsLocalNetworking"] as? Bool == true)
  }

  @Test
  func sourceEntitlementsStayAtTheDeclaredMinimum() throws {
    let data = try Data(contentsOf: Self.entitlementsURL)
    let propertyList = try PropertyListSerialization.propertyList(
      from: data,
      options: [],
      format: nil
    )
    let entitlements = try #require(propertyList as? [String: Any])

    #expect(
      Set(entitlements.keys)
        == Set([
          "com.apple.security.app-sandbox",
          "com.apple.security.device.audio-input",
          "com.apple.security.network.client",
        ])
    )
    #expect(entitlements.values.allSatisfy { ($0 as? Bool) == true })
  }

  @Test
  @MainActor
  func packagedOrionNeutralSpriteIsLoadable() throws {
    let bundle = Bundle(for: AppDelegate.self)
    let url = try #require(CompanionAssets.orionNeutralURL(in: bundle))

    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(CompanionAssets.orionNeutralImage(in: bundle) != nil)
  }

  @Test
  @MainActor
  func companionPanelCannotActivateOrObscureItsTransparentCanvas() {
    let panel = CompanionPanel(
      image: NSImage(size: CompanionStage.canvasSize),
      canvasSize: CompanionStage.canvasSize
    )

    #expect(panel.styleMask.contains(.borderless))
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(!panel.canBecomeKey)
    #expect(!panel.canBecomeMain)
    #expect(!panel.isOpaque)
    #expect(panel.backgroundColor == .clear)
    #expect(panel.ignoresMouseEvents)
  }

  private static var entitlementsURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "ReadyPlayerTwo/ReadyPlayerTwo.entitlements")
  }
}
