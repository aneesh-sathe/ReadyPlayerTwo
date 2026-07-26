import Foundation

public enum AnimationManifestError: Error, Equatable, Sendable {
  case avatarMismatch(expected: CompanionAvatar, actualIdentifier: String)
  case invalidCanvas(SpriteCanvas)
  case missingFrame(state: AnimationStateID, path: String)
  case invalidFramesPerSecond(state: AnimationStateID, value: Double)
  case emptyFrames(state: AnimationStateID)
  case missingAnchor(avatar: CompanionAvatar, role: SpriteAnchorRole)
  case unsupportedAnchor(avatar: CompanionAvatar, name: String)
  case anchorOutsideCanvas(
    role: SpriteAnchorRole,
    anchor: SpriteAnchor,
    canvas: SpriteCanvas
  )
  case unsupportedState(avatar: CompanionAvatar, state: AnimationStateID)
  case missingState(avatar: CompanionAvatar, state: AnimationStateID)
  case missingReferencedState(from: AnimationStateID, to: AnimationStateID)
  case unsafeFramePath(state: AnimationStateID, path: String)
  case invalidPNG(state: AnimationStateID, path: String)
  case illegalTransition(
    avatar: CompanionAvatar,
    from: AnimationStateID,
    to: AnimationStateID
  )
  case missingRequiredTransition(
    avatar: CompanionAvatar,
    from: AnimationStateID,
    to: AnimationStateID
  )
  case invalidFrameDimensions(
    state: AnimationStateID,
    path: String,
    expectedWidth: Int,
    expectedHeight: Int,
    actualWidth: Int,
    actualHeight: Int
  )
}

public struct AnimationStateID: RawRepresentable, Hashable, Codable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(_ rawValue: String) {
    self.init(rawValue: rawValue)
  }
}

public struct SpriteCanvas: Equatable, Sendable {
  public let width: Int
  public let height: Int
  public let format: String

  public init(width: Int, height: Int, format: String) {
    self.width = width
    self.height = height
    self.format = format
  }
}

public enum SpriteAnchorRole: String, Hashable, Sendable {
  case grounded
  case airborne
  case airborneOrWall
}

public struct SpriteAnchor: Equatable, Sendable {
  public let x: Int
  public let y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }
}

public struct SpriteAnimation: Equatable, Sendable {
  public let id: AnimationStateID
  public let frames: [URL]
  public let framesPerSecond: Double
  public let loops: Bool
  public let nextStates: [AnimationStateID]

  public var durationSeconds: Double {
    Double(frames.count) / framesPerSecond
  }

  public init(
    id: AnimationStateID,
    frames: [URL],
    framesPerSecond: Double,
    loops: Bool,
    nextStates: [AnimationStateID]
  ) {
    self.id = id
    self.frames = frames
    self.framesPerSecond = framesPerSecond
    self.loops = loops
    self.nextStates = nextStates
  }
}

public struct AvatarAnimationManifest: Equatable, Sendable {
  public let avatar: CompanionAvatar
  public let characterIdentifier: String
  public let canvas: SpriteCanvas
  public let anchors: [SpriteAnchorRole: SpriteAnchor]
  public let animations: [AnimationStateID: SpriteAnimation]

  public var referencedFrameCount: Int {
    animations.values.reduce(into: 0) { count, animation in
      count += animation.frames.count
    }
  }

  public init(
    avatar: CompanionAvatar,
    characterIdentifier: String,
    canvas: SpriteCanvas,
    anchors: [SpriteAnchorRole: SpriteAnchor],
    animations: [AnimationStateID: SpriteAnimation]
  ) {
    self.avatar = avatar
    self.characterIdentifier = characterIdentifier
    self.canvas = canvas
    self.anchors = anchors
    self.animations = animations
  }

  public func animation(named name: String) -> SpriteAnimation? {
    animations[AnimationStateID(name)]
  }
}

public struct AnimationManifestLoader: Sendable {
  public init() {}

  public func load(
    avatar: CompanionAvatar,
    from rootURL: URL
  ) throws -> AvatarAnimationManifest {
    let normalizedRootURL = rootURL.standardizedFileURL
    let manifestURL = normalizedRootURL.appending(path: "animation-manifest.json")
    let data = try Data(contentsOf: manifestURL)
    let decoded = try JSONDecoder().decode(DecodedManifest.self, from: data)
    let expectedCharacterIdentifier =
      switch avatar {
      case .orion:
        "warrior-avatar"
      case .athena:
        "female-angel"
      }
    guard decoded.character == expectedCharacterIdentifier else {
      throw AnimationManifestError.avatarMismatch(
        expected: avatar,
        actualIdentifier: decoded.character
      )
    }
    let canvas = SpriteCanvas(
      width: decoded.canvas.width,
      height: decoded.canvas.height,
      format: decoded.canvas.format
    )
    guard canvas.width > 0, canvas.height > 0, canvas.format == "RGBA PNG" else {
      throw AnimationManifestError.invalidCanvas(canvas)
    }
    let allowedStates = ManifestContract.allowedStates(for: avatar)
    if let unsupportedState = decoded.states.keys.sorted().first(where: {
      !allowedStates.contains(AnimationStateID($0))
    }) {
      throw AnimationManifestError.unsupportedState(
        avatar: avatar,
        state: AnimationStateID(unsupportedState)
      )
    }
    let decodedStateIDs = Set(decoded.states.keys.map { AnimationStateID($0) })
    if let missingState = allowedStates.subtracting(decodedStateIDs).sorted(by: {
      $0.rawValue < $1.rawValue
    }).first {
      throw AnimationManifestError.missingState(
        avatar: avatar,
        state: missingState
      )
    }
    var declaredTransitions = Set<StateTransition>()
    for name in decoded.states.keys.sorted() {
      guard let state = decoded.states[name] else {
        continue
      }
      let references =
        state.next.map { [$0] }
        ?? state.nextOptions
        ?? []
      for reference in references where decoded.states[reference] == nil {
        throw AnimationManifestError.missingReferencedState(
          from: AnimationStateID(name),
          to: AnimationStateID(reference)
        )
      }
      for reference in references {
        let transition = StateTransition(
          from: AnimationStateID(name),
          to: AnimationStateID(reference)
        )
        declaredTransitions.insert(transition)
        guard ManifestContract.legalReferences(for: avatar).contains(transition) else {
          throw AnimationManifestError.illegalTransition(
            avatar: avatar,
            from: transition.from,
            to: transition.to
          )
        }
      }
    }
    let requiredTransitions = ManifestContract.legalReferences(for: avatar)
    if let missingTransition = requiredTransitions.subtracting(declaredTransitions).sorted(by: {
      ($0.from.rawValue, $0.to.rawValue) < ($1.from.rawValue, $1.to.rawValue)
    }).first {
      throw AnimationManifestError.missingRequiredTransition(
        avatar: avatar,
        from: missingTransition.from,
        to: missingTransition.to
      )
    }

    for (name, state) in decoded.states {
      guard state.fps.isFinite, state.fps > 0 else {
        throw AnimationManifestError.invalidFramesPerSecond(
          state: AnimationStateID(name),
          value: state.fps
        )
      }
      guard !state.frames.isEmpty else {
        throw AnimationManifestError.emptyFrames(state: AnimationStateID(name))
      }

      for path in state.frames {
        let frameURL = try validatedFrameURL(
          for: path,
          state: AnimationStateID(name),
          rootURL: normalizedRootURL
        )
        guard FileManager.default.fileExists(atPath: frameURL.path) else {
          throw AnimationManifestError.missingFrame(
            state: AnimationStateID(name),
            path: path
          )
        }

        let frameData = try Data(contentsOf: frameURL)
        guard
          let metadata = PNGHeader.metadata(in: frameData),
          metadata.bitDepth == 8,
          metadata.colorType == 6
        else {
          throw AnimationManifestError.invalidPNG(
            state: AnimationStateID(name),
            path: path
          )
        }
        guard
          metadata.width == decoded.canvas.width,
          metadata.height == decoded.canvas.height
        else {
          throw AnimationManifestError.invalidFrameDimensions(
            state: AnimationStateID(name),
            path: path,
            expectedWidth: decoded.canvas.width,
            expectedHeight: decoded.canvas.height,
            actualWidth: metadata.width,
            actualHeight: metadata.height
          )
        }
      }
    }

    let requiredAnchorRoles: [SpriteAnchorRole] =
      switch avatar {
      case .orion:
        [.grounded, .airborneOrWall]
      case .athena:
        [.grounded, .airborne]
      }
    let requiredAnchorNames = Set(requiredAnchorRoles.map(\.rawValue))
    if let unsupportedAnchor = decoded.anchors.keys.sorted().first(where: {
      !requiredAnchorNames.contains($0)
    }) {
      throw AnimationManifestError.unsupportedAnchor(
        avatar: avatar,
        name: unsupportedAnchor
      )
    }
    let anchors: [SpriteAnchorRole: SpriteAnchor] = Dictionary(
      uniqueKeysWithValues: decoded.anchors.compactMap { name, anchor in
        guard let role = SpriteAnchorRole(rawValue: name) else {
          return nil
        }
        return (role, SpriteAnchor(x: anchor.x, y: anchor.y))
      }
    )
    for role in requiredAnchorRoles where anchors[role] == nil {
      throw AnimationManifestError.missingAnchor(
        avatar: avatar,
        role: role
      )
    }
    for (role, anchor) in anchors {
      guard
        anchor.x >= 0,
        anchor.x < canvas.width,
        anchor.y >= 0,
        anchor.y < canvas.height
      else {
        throw AnimationManifestError.anchorOutsideCanvas(
          role: role,
          anchor: anchor,
          canvas: canvas
        )
      }
    }
    let animations = Dictionary(
      uniqueKeysWithValues: decoded.states.map { name, state in
        let id = AnimationStateID(name)
        let nextStates =
          state.next.map { [AnimationStateID($0)] }
          ?? state.nextOptions?.map { AnimationStateID($0) }
          ?? []
        let frames = state.frames.map {
          normalizedRootURL.appending(path: $0).standardizedFileURL
        }
        return (
          id,
          SpriteAnimation(
            id: id,
            frames: frames,
            framesPerSecond: state.fps,
            loops: state.loop,
            nextStates: nextStates
          )
        )
      }
    )

    return AvatarAnimationManifest(
      avatar: avatar,
      characterIdentifier: decoded.character,
      canvas: canvas,
      anchors: anchors,
      animations: animations
    )
  }

  private func validatedFrameURL(
    for path: String,
    state: AnimationStateID,
    rootURL: URL
  ) throws -> URL {
    let candidate = rootURL.appending(path: path).standardizedFileURL
    let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
    guard
      !path.isEmpty,
      !path.hasPrefix("/"),
      URL(fileURLWithPath: path).pathExtension.lowercased() == "png",
      candidate.path.hasPrefix(rootPath)
    else {
      throw AnimationManifestError.unsafeFramePath(
        state: state,
        path: path
      )
    }

    return candidate
  }
}

private struct DecodedManifest: Decodable {
  let character: String
  let canvas: DecodedCanvas
  let anchors: [String: DecodedAnchor]
  let states: [String: DecodedAnimation]
}

private struct DecodedCanvas: Decodable {
  let width: Int
  let height: Int
  let format: String
}

private struct DecodedAnchor: Decodable {
  let x: Int
  let y: Int
}

private struct DecodedAnimation: Decodable {
  let fps: Double
  let loop: Bool
  let frames: [String]
  let next: String?
  let nextOptions: [String]?
}

private enum PNGHeader {
  private static let signature: [UInt8] = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  ]

  static func metadata(in data: Data) -> PNGMetadata? {
    guard data.count >= 26 else {
      return nil
    }
    guard data.prefix(signature.count).elementsEqual(signature) else {
      return nil
    }
    guard String(decoding: data[12..<16], as: UTF8.self) == "IHDR" else {
      return nil
    }

    return PNGMetadata(
      width: integer(from: data[16..<20]),
      height: integer(from: data[20..<24]),
      bitDepth: data[24],
      colorType: data[25]
    )
  }

  private static func integer(from bytes: Data.SubSequence) -> Int {
    bytes.reduce(into: 0) { value, byte in
      value = (value << 8) | Int(byte)
    }
  }
}

private struct PNGMetadata {
  let width: Int
  let height: Int
  let bitDepth: UInt8
  let colorType: UInt8
}

private enum ManifestContract {
  private static let sharedStates = Set(
    [
      "front-neutral",
      "back-neutral",
      "left-neutral",
      "right-neutral",
      "front-happy",
      "back-happy",
      "left-happy",
      "right-happy",
      "front-angry",
      "back-angry",
      "left-angry",
      "right-angry",
      "walk-left",
      "walk-right",
    ].map { AnimationStateID($0) }
  )

  static func allowedStates(for avatar: CompanionAvatar) -> Set<AnimationStateID> {
    switch avatar {
    case .orion:
      sharedStates.union(
        [
          "climb-up",
          "jump-down",
          "wall-cling",
          "climb-entry-left",
          "climb-entry-right",
          "landing-left",
          "landing-right",
        ].map { AnimationStateID($0) }
      )
    case .athena:
      sharedStates.union(
        [
          "glide-up",
          "glide-down",
          "hover",
          "takeoff-left",
          "takeoff-right",
          "landing-left",
          "landing-right",
        ].map { AnimationStateID($0) }
      )
    }
  }

  static func legalReferences(for avatar: CompanionAvatar) -> Set<StateTransition> {
    let pairs: [(String, String)] =
      switch avatar {
      case .orion:
        [
          ("climb-entry-left", "wall-cling"),
          ("climb-entry-right", "wall-cling"),
          ("jump-down", "landing-left"),
          ("jump-down", "landing-right"),
          ("landing-left", "walk-left"),
          ("landing-right", "walk-right"),
        ]
      case .athena:
        [
          ("takeoff-left", "hover"),
          ("takeoff-right", "hover"),
          ("landing-left", "left-neutral"),
          ("landing-right", "right-neutral"),
        ]
      }

    return Set(
      pairs.map { from, to in
        StateTransition(
          from: AnimationStateID(from),
          to: AnimationStateID(to)
        )
      }
    )
  }
}

private struct StateTransition: Hashable {
  let from: AnimationStateID
  let to: AnimationStateID
}
