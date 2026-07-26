import CompanionRuntime
import Foundation
import Testing

@Suite
struct AnimationManifestTests {
  @Test
  func loadsBothAuthoritativeManifestShapesFromCallerSuppliedRoots() throws {
    let loader = AnimationManifestLoader()

    let orion = try loader.load(
      avatar: .orion,
      from: Self.avatarRoot(named: "avatar-orion")
    )
    let athena = try loader.load(
      avatar: .athena,
      from: Self.avatarRoot(named: "avatar-athena")
    )

    #expect(orion.avatar == .orion)
    #expect(orion.characterIdentifier == "warrior-avatar")
    #expect(orion.canvas == SpriteCanvas(width: 512, height: 512, format: "RGBA PNG"))
    #expect(
      orion.anchors == [
        .grounded: SpriteAnchor(x: 256, y: 500),
        .airborneOrWall: SpriteAnchor(x: 256, y: 256),
      ]
    )
    #expect(orion.animations.count == 21)
    #expect(orion.referencedFrameCount == 64)
    #expect(
      orion.animation(named: "jump-down")?.nextStates
        == [AnimationStateID("landing-left"), AnimationStateID("landing-right")]
    )

    #expect(athena.avatar == .athena)
    #expect(athena.characterIdentifier == "female-angel")
    #expect(athena.canvas == SpriteCanvas(width: 512, height: 512, format: "RGBA PNG"))
    #expect(
      athena.anchors == [
        .grounded: SpriteAnchor(x: 256, y: 500),
        .airborne: SpriteAnchor(x: 256, y: 256),
      ]
    )
    #expect(athena.animations.count == 21)
    #expect(athena.referencedFrameCount == 64)
    #expect(
      athena.animation(named: "takeoff-left")?.nextStates
        == [AnimationStateID("hover")]
    )
  }

  @Test
  func rejectsAManifestWhenAnyReferencedFrameIsMissing() throws {
    let fixture = try Self.copyFixture(named: "avatar-orion")
    defer {
      try? FileManager.default.removeItem(at: fixture)
    }
    let missingPath = "expressions/warrior-front-neutral.png"
    try FileManager.default.removeItem(at: fixture.appending(path: missingPath))

    #expect(
      throws: AnimationManifestError.missingFrame(
        state: AnimationStateID("front-neutral"),
        path: missingPath
      )
    ) {
      try AnimationManifestLoader().load(avatar: .orion, from: fixture)
    }
  }

  @Test
  func rejectsAReferencedFrameWhoseDimensionsDifferFromTheCanvas() throws {
    let fixture = try Self.copyFixture(named: "avatar-orion")
    defer {
      try? FileManager.default.removeItem(at: fixture)
    }
    let framePath = "expressions/warrior-front-neutral.png"
    let frameURL = fixture.appending(path: framePath)
    var frameData = try Data(contentsOf: frameURL)
    frameData.replaceSubrange(16..<20, with: [0, 0, 2, 128])
    frameData.replaceSubrange(20..<24, with: [0, 0, 1, 182])
    try frameData.write(to: frameURL, options: .atomic)

    #expect(
      throws: AnimationManifestError.invalidFrameDimensions(
        state: AnimationStateID("front-neutral"),
        path: framePath,
        expectedWidth: 512,
        expectedHeight: 512,
        actualWidth: 640,
        actualHeight: 438
      )
    ) {
      try AnimationManifestLoader().load(avatar: .orion, from: fixture)
    }
  }

  @Test
  func rejectsNonPositiveFrameRatesBeforeAnimationDurationCanBecomeInvalid() throws {
    let fixture = try Self.copyFixture(named: "avatar-athena")
    defer {
      try? FileManager.default.removeItem(at: fixture)
    }
    try Self.setStateValue(
      0,
      forKey: "fps",
      state: "hover",
      in: fixture
    )

    #expect(
      throws: AnimationManifestError.invalidFramesPerSecond(
        state: AnimationStateID("hover"),
        value: 0
      )
    ) {
      try AnimationManifestLoader().load(avatar: .athena, from: fixture)
    }
  }

  @Test
  func rejectsAnAnimationWhoseEmptyFrameListWouldHaveZeroDuration() throws {
    let fixture = try Self.copyFixture(named: "avatar-orion")
    defer {
      try? FileManager.default.removeItem(at: fixture)
    }
    try Self.setStateValue(
      [String](),
      forKey: "frames",
      state: "wall-cling",
      in: fixture
    )

    #expect(
      throws: AnimationManifestError.emptyFrames(
        state: AnimationStateID("wall-cling")
      )
    ) {
      try AnimationManifestLoader().load(avatar: .orion, from: fixture)
    }
  }

  @Test
  func requiresTheAnchorRolesDefinedByEachAuthoritativeShape() throws {
    let fixture = try Self.copyFixture(named: "avatar-athena")
    defer {
      try? FileManager.default.removeItem(at: fixture)
    }
    try Self.removeAnchor(named: "airborne", from: fixture)

    #expect(
      throws: AnimationManifestError.missingAnchor(
        avatar: .athena,
        role: .airborne
      )
    ) {
      try AnimationManifestLoader().load(avatar: .athena, from: fixture)
    }
  }

  @Test
  func rejectsAnchorsOutsideTheDeclaredCanvas() throws {
    let fixture = try Self.copyFixture(named: "avatar-orion")
    defer {
      try? FileManager.default.removeItem(at: fixture)
    }
    try Self.setAnchor(
      named: "grounded",
      x: 513,
      y: 500,
      in: fixture
    )

    #expect(
      throws: AnimationManifestError.anchorOutsideCanvas(
        role: .grounded,
        anchor: SpriteAnchor(x: 513, y: 500),
        canvas: SpriteCanvas(width: 512, height: 512, format: "RGBA PNG")
      )
    ) {
      try AnimationManifestLoader().load(avatar: .orion, from: fixture)
    }
  }

  @Test
  func rejectsStatesOutsideAnAvatarsLegalCapabilities() throws {
    let fixture = try Self.copyFixture(named: "avatar-athena")
    defer {
      try? FileManager.default.removeItem(at: fixture)
    }
    try Self.renameState(
      from: "hover",
      to: "fast-horizontal-flight",
      in: fixture
    )

    #expect(
      throws: AnimationManifestError.unsupportedState(
        avatar: .athena,
        state: AnimationStateID("fast-horizontal-flight")
      )
    ) {
      try AnimationManifestLoader().load(avatar: .athena, from: fixture)
    }
  }

  @Test
  func requiresEveryStateInAnAvatarsLegalCapabilitySet() throws {
    let fixture = try Self.copyFixture(named: "avatar-orion")
    defer {
      try? FileManager.default.removeItem(at: fixture)
    }
    try Self.removeState(named: "climb-up", from: fixture)

    #expect(
      throws: AnimationManifestError.missingState(
        avatar: .orion,
        state: AnimationStateID("climb-up")
      )
    ) {
      try AnimationManifestLoader().load(avatar: .orion, from: fixture)
    }
  }

  @Test
  func rejectsTransitionsToStatesAbsentFromTheManifest() throws {
    let fixture = try Self.copyFixture(named: "avatar-orion")
    defer {
      try? FileManager.default.removeItem(at: fixture)
    }
    try Self.setStateValue(
      "climb-down",
      forKey: "next",
      state: "landing-left",
      in: fixture
    )

    #expect(
      throws: AnimationManifestError.missingReferencedState(
        from: AnimationStateID("landing-left"),
        to: AnimationStateID("climb-down")
      )
    ) {
      try AnimationManifestLoader().load(avatar: .orion, from: fixture)
    }
  }

  @Test
  func rejectsReferencedTransitionsOutsideLegalCapabilities() throws {
    let fixture = try Self.copyFixture(named: "avatar-athena")
    defer {
      try? FileManager.default.removeItem(at: fixture)
    }
    try Self.setStateValue(
      "walk-right",
      forKey: "next",
      state: "takeoff-left",
      in: fixture
    )

    #expect(
      throws: AnimationManifestError.illegalTransition(
        avatar: .athena,
        from: AnimationStateID("takeoff-left"),
        to: AnimationStateID("walk-right")
      )
    ) {
      try AnimationManifestLoader().load(avatar: .athena, from: fixture)
    }
  }

  @Test
  func rejectsReferencedPathsThatEscapeTheCallerSuppliedRoot() throws {
    let fixture = try Self.copyFixture(named: "avatar-orion")
    defer {
      try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent())
    }
    let outsideURL = fixture.deletingLastPathComponent().appending(path: "outside.png")
    try FileManager.default.copyItem(
      at: fixture.appending(path: "expressions/warrior-front-neutral.png"),
      to: outsideURL
    )
    let escapedPath = "../outside.png"
    try Self.setStateValue(
      [escapedPath],
      forKey: "frames",
      state: "front-neutral",
      in: fixture
    )

    #expect(
      throws: AnimationManifestError.unsafeFramePath(
        state: AnimationStateID("front-neutral"),
        path: escapedPath
      )
    ) {
      try AnimationManifestLoader().load(avatar: .orion, from: fixture)
    }
  }

  @Test
  func rejectsReferencedFilesThatAreNotRgbaPngFrames() throws {
    let fixture = try Self.copyFixture(named: "avatar-athena")
    defer {
      try? FileManager.default.removeItem(at: fixture)
    }
    let framePath = "expressions/angel-front-neutral.png"
    try Data("not a PNG".utf8).write(
      to: fixture.appending(path: framePath),
      options: .atomic
    )

    #expect(
      throws: AnimationManifestError.invalidPNG(
        state: AnimationStateID("front-neutral"),
        path: framePath
      )
    ) {
      try AnimationManifestLoader().load(avatar: .athena, from: fixture)
    }
  }

  @Test
  func rejectsAJsonShapeThatDoesNotMatchTheRequestedAvatar() {
    #expect(
      throws: AnimationManifestError.avatarMismatch(
        expected: .orion,
        actualIdentifier: "female-angel"
      )
    ) {
      try AnimationManifestLoader().load(
        avatar: .orion,
        from: Self.avatarRoot(named: "avatar-athena")
      )
    }
  }

  @Test
  func rejectsANonPositiveCanvasBeforeInspectingFrames() throws {
    let fixture = try Self.copyFixture(named: "avatar-orion")
    defer {
      try? FileManager.default.removeItem(at: fixture)
    }
    try Self.setCanvas(
      width: 0,
      height: 512,
      format: "RGBA PNG",
      in: fixture
    )

    #expect(
      throws: AnimationManifestError.invalidCanvas(
        SpriteCanvas(width: 0, height: 512, format: "RGBA PNG")
      )
    ) {
      try AnimationManifestLoader().load(avatar: .orion, from: fixture)
    }
  }

  @Test
  func rejectsAnchorRolesOutsideTheRequestedJsonShape() throws {
    let fixture = try Self.copyFixture(named: "avatar-athena")
    defer {
      try? FileManager.default.removeItem(at: fixture)
    }
    try Self.setAnchor(
      named: "wingTip",
      x: 256,
      y: 256,
      in: fixture
    )

    #expect(
      throws: AnimationManifestError.unsupportedAnchor(
        avatar: .athena,
        name: "wingTip"
      )
    ) {
      try AnimationManifestLoader().load(avatar: .athena, from: fixture)
    }
  }

  @Test
  func requiresEveryAuthoritativeStateTransition() throws {
    let fixture = try Self.copyFixture(named: "avatar-orion")
    defer {
      try? FileManager.default.removeItem(at: fixture)
    }
    try Self.setStateValue(
      NSNull(),
      forKey: "next",
      state: "climb-entry-left",
      in: fixture
    )

    #expect(
      throws: AnimationManifestError.missingRequiredTransition(
        avatar: .orion,
        from: AnimationStateID("climb-entry-left"),
        to: AnimationStateID("wall-cling")
      )
    ) {
      try AnimationManifestLoader().load(avatar: .orion, from: fixture)
    }
  }

  private static func setCanvas(
    width: Int,
    height: Int,
    format: String,
    in root: URL
  ) throws {
    let manifestURL = root.appending(path: "animation-manifest.json")
    let data = try Data(contentsOf: manifestURL)
    var manifest = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    manifest["canvas"] = [
      "width": width,
      "height": height,
      "format": format,
    ]
    let rewritten = try JSONSerialization.data(
      withJSONObject: manifest,
      options: [.prettyPrinted, .sortedKeys]
    )
    try rewritten.write(to: manifestURL, options: .atomic)
  }

  private static func removeState(named name: String, from root: URL) throws {
    let manifestURL = root.appending(path: "animation-manifest.json")
    let data = try Data(contentsOf: manifestURL)
    var manifest = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    var states = try #require(manifest["states"] as? [String: Any])
    states.removeValue(forKey: name)
    manifest["states"] = states
    let rewritten = try JSONSerialization.data(
      withJSONObject: manifest,
      options: [.prettyPrinted, .sortedKeys]
    )
    try rewritten.write(to: manifestURL, options: .atomic)
  }

  private static func renameState(
    from oldName: String,
    to newName: String,
    in root: URL
  ) throws {
    let manifestURL = root.appending(path: "animation-manifest.json")
    let data = try Data(contentsOf: manifestURL)
    var manifest = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    var states = try #require(manifest["states"] as? [String: Any])
    states[newName] = states.removeValue(forKey: oldName)
    manifest["states"] = states
    let rewritten = try JSONSerialization.data(
      withJSONObject: manifest,
      options: [.prettyPrinted, .sortedKeys]
    )
    try rewritten.write(to: manifestURL, options: .atomic)
  }

  private static func setAnchor(
    named name: String,
    x: Int,
    y: Int,
    in root: URL
  ) throws {
    let manifestURL = root.appending(path: "animation-manifest.json")
    let data = try Data(contentsOf: manifestURL)
    var manifest = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    var anchors = try #require(manifest["anchors"] as? [String: Any])
    anchors[name] = ["x": x, "y": y]
    manifest["anchors"] = anchors
    let rewritten = try JSONSerialization.data(
      withJSONObject: manifest,
      options: [.prettyPrinted, .sortedKeys]
    )
    try rewritten.write(to: manifestURL, options: .atomic)
  }

  private static func removeAnchor(named name: String, from root: URL) throws {
    let manifestURL = root.appending(path: "animation-manifest.json")
    let data = try Data(contentsOf: manifestURL)
    var manifest = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    var anchors = try #require(manifest["anchors"] as? [String: Any])
    anchors.removeValue(forKey: name)
    manifest["anchors"] = anchors
    let rewritten = try JSONSerialization.data(
      withJSONObject: manifest,
      options: [.prettyPrinted, .sortedKeys]
    )
    try rewritten.write(to: manifestURL, options: .atomic)
  }

  private static func setStateValue(
    _ value: Any,
    forKey key: String,
    state stateName: String,
    in root: URL
  ) throws {
    let manifestURL = root.appending(path: "animation-manifest.json")
    let data = try Data(contentsOf: manifestURL)
    var manifest = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    var states = try #require(manifest["states"] as? [String: Any])
    var state = try #require(states[stateName] as? [String: Any])
    state[key] = value
    states[stateName] = state
    manifest["states"] = states
    let rewritten = try JSONSerialization.data(
      withJSONObject: manifest,
      options: [.prettyPrinted, .sortedKeys]
    )
    try rewritten.write(to: manifestURL, options: .atomic)
  }

  private static func copyFixture(named name: String) throws -> URL {
    let destination = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
      .appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(
      at: avatarRoot(named: name),
      to: destination
    )
    return destination
  }

  private static func avatarRoot(named name: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "assets/\(name)", directoryHint: .isDirectory)
  }
}
