import AppKit
import CompanionRuntime
import Testing

@testable import ReadyPlayerTwo

@Suite(.serialized)
@MainActor
struct AvatarSpriteVisualContractTests {
  @Test
  func everyManifestFrameHasAStableTransparentCPURender() throws {
    let entries = try makeVisualContractEntries()
    let expected = AvatarSpriteVisualBaselines.entries

    if ProcessInfo.processInfo.environment[
      "READY_PLAYER_TWO_RECORD_VISUAL_BASELINES"
    ] == "1" {
      print("VISUAL_BASELINES_BEGIN")
      print(Self.baselineText(from: entries))
      print("VISUAL_BASELINES_END")
    }

    #expect(entries.count == 130)
    guard !expected.isEmpty else {
      #expect(
        !expected.isEmpty,
        Comment(rawValue: Self.baselineText(from: entries))
      )
      return
    }
    #expect(Set(entries.keys) == Set(expected.keys))
    for key in entries.keys.sorted() {
      #expect(
        entries[key] == expected[key],
        Comment(rawValue: key)
      )
    }
  }

  // The manifests expose one grounded anchor per avatar, not per-frame foot
  // landmarks. This proves contact continuity at declared transitions only.
  @Test
  func groundedTransitionsKeepContactWithinOnePointOfTheirAnchor() throws {
    let transitions: [GroundedTransition] = [
      .init(
        avatar: .orion,
        from: .init(state: "landing-left", frame: 3),
        to: .init(state: "walk-left", frame: 0)
      ),
      .init(
        avatar: .orion,
        from: .init(state: "landing-right", frame: 3),
        to: .init(state: "walk-right", frame: 0)
      ),
      .init(
        avatar: .athena,
        from: .init(state: "landing-left", frame: 3),
        to: .init(state: "left-neutral", frame: 0)
      ),
      .init(
        avatar: .athena,
        from: .init(state: "landing-right", frame: 3),
        to: .init(state: "right-neutral", frame: 0)
      ),
      .init(
        avatar: .athena,
        from: .init(state: "left-neutral", frame: 0),
        to: .init(state: "takeoff-left", frame: 0)
      ),
      .init(
        avatar: .athena,
        from: .init(state: "right-neutral", frame: 0),
        to: .init(state: "takeoff-right", frame: 0)
      ),
    ]
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)

    for transition in transitions {
      let manifest = try AnimationManifestLoader().load(
        avatar: transition.avatar,
        from: CompanionAssets.avatarRootURL(
          for: transition.avatar,
          under: resourceURL
        )
      )

      for scale in [1, 2] {
        let fromBottom = try contactBottom(
          transition.from,
          manifest: manifest,
          scale: scale
        )
        let toBottom = try contactBottom(
          transition.to,
          manifest: manifest,
          scale: scale
        )
        let anchor = try #require(manifest.anchors[.grounded])
        let scaledAnchorY =
          anchor.y * Int(CompanionStage.canvasSize.height) * scale
          / manifest.canvas.height
        let context =
          "\(transition.avatar.rawValue) "
          + "\(transition.from.state) to \(transition.to.state) \(scale)x"

        #expect(
          abs(Double(scaledAnchorY - fromBottom) / Double(scale)) <= 1,
          Comment(rawValue: context)
        )
        #expect(
          abs(Double(scaledAnchorY - toBottom) / Double(scale)) <= 1,
          Comment(rawValue: context)
        )
        #expect(
          abs(Double(fromBottom - toBottom) / Double(scale)) <= 1,
          Comment(rawValue: context)
        )
      }
    }
  }

  private func makeVisualContractEntries() throws -> [String: String] {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    var entries: [String: String] = [:]

    for avatar in CompanionAvatar.allCases.sorted(by: {
      $0.rawValue < $1.rawValue
    }) {
      let manifest = try AnimationManifestLoader().load(
        avatar: avatar,
        from: CompanionAssets.avatarRootURL(
          for: avatar,
          under: resourceURL
        )
      )
      entries["\(avatar.rawValue)/anchors"] =
        try anchorSignature(for: manifest)

      for state in manifest.animations.keys.sorted(by: {
        $0.rawValue < $1.rawValue
      }) {
        let animation = try #require(manifest.animations[state])

        for (index, frameURL) in animation.frames.enumerated() {
          let key = String(
            format: "%@/%@/%02d",
            avatar.rawValue,
            state.rawValue,
            index
          )
          var renderSignatures: [String] = []

          for scale in [1, 2] {
            let rendered = try CPUVisualRenderer.render(
              imageURL: frameURL,
              pointSize: CompanionStage.canvasSize,
              scale: scale
            )

            #expect(
              rendered.width == Int(CompanionStage.canvasSize.width)
                * scale,
              Comment(rawValue: key)
            )
            #expect(
              rendered.height == Int(CompanionStage.canvasSize.height)
                * scale,
              Comment(rawValue: key)
            )
            #expect(
              rendered.hasCanonicalTransparentBackground,
              Comment(rawValue: key)
            )
            #expect(
              rendered.alphaPixelCount > 0,
              Comment(rawValue: key)
            )
            #expect(
              rendered.alphaBounds != nil,
              Comment(rawValue: key)
            )
            renderSignatures.append("\(scale)x \(rendered.signature)")
          }

          entries[key] = renderSignatures.joined(separator: " ; ")
        }
      }
    }

    return entries
  }

  private func anchorSignature(
    for manifest: AvatarAnimationManifest
  ) throws -> String {
    let source = try anchorValues(
      for: manifest,
      width: manifest.canvas.width,
      height: manifest.canvas.height
    )
    let oneTimes = try anchorValues(
      for: manifest,
      width: Int(CompanionStage.canvasSize.width),
      height: Int(CompanionStage.canvasSize.height)
    )
    let twoTimes = try anchorValues(
      for: manifest,
      width: Int(CompanionStage.canvasSize.width) * 2,
      height: Int(CompanionStage.canvasSize.height) * 2
    )

    return
      "source \(source) ; 1x \(oneTimes) ; 2x \(twoTimes)"
  }

  private func contactBottom(
    _ contact: GroundedContact,
    manifest: AvatarAnimationManifest,
    scale: Int
  ) throws -> Int {
    let animation = try #require(
      manifest.animation(named: contact.state)
    )
    let frameURL = try #require(
      animation.frames.indices.contains(contact.frame)
        ? animation.frames[contact.frame]
        : nil
    )
    let rendered = try CPUVisualRenderer.render(
      imageURL: frameURL,
      pointSize: CompanionStage.canvasSize,
      scale: scale
    )
    return try #require(rendered.alphaBounds).maxY
  }

  private func anchorValues(
    for manifest: AvatarAnimationManifest,
    width: Int,
    height: Int
  ) throws -> String {
    try manifest.anchors.keys.sorted(by: {
      $0.rawValue < $1.rawValue
    }).map { role in
      let anchor = try #require(manifest.anchors[role])
      #expect(
        anchor.x * width % manifest.canvas.width == 0,
        Comment(rawValue: "\(manifest.avatar.rawValue)/\(role.rawValue)")
      )
      #expect(
        anchor.y * height % manifest.canvas.height == 0,
        Comment(rawValue: "\(manifest.avatar.rawValue)/\(role.rawValue)")
      )
      let x = anchor.x * width / manifest.canvas.width
      let y = anchor.y * height / manifest.canvas.height
      return "\(role.rawValue)@\(x),\(y)"
    }.joined(separator: " ")
  }

  private static func baselineText(
    from entries: [String: String]
  ) -> String {
    entries.keys.sorted().compactMap { key in
      entries[key].map { "\(key)|\($0)" }
    }.joined(separator: "\n")
  }
}

private struct GroundedContact {
  let state: String
  let frame: Int
}

private struct GroundedTransition {
  let avatar: CompanionAvatar
  let from: GroundedContact
  let to: GroundedContact
}
