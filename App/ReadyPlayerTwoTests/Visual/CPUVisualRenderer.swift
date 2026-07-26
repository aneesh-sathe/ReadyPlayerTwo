import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

struct VisualPixelBounds: Equatable {
  let minX: Int
  let minY: Int
  let maxX: Int
  let maxY: Int

  var description: String {
    "\(minX),\(minY),\(maxX),\(maxY)"
  }
}

struct CPURenderedVisual {
  let width: Int
  let height: Int
  let rgbaBytes: [UInt8]
  let alphaBounds: VisualPixelBounds?
  let alphaPixelCount: Int

  var sha256: String {
    SHA256.hash(data: Data(rgbaBytes))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  var cornerAlpha: [UInt8] {
    [
      alpha(x: 0, y: 0),
      alpha(x: width - 1, y: 0),
      alpha(x: 0, y: height - 1),
      alpha(x: width - 1, y: height - 1),
    ]
  }

  var hasCanonicalTransparentBackground: Bool {
    var foundTransparentPixel = false

    for pixelOffset in stride(from: 0, to: rgbaBytes.count, by: 4) {
      guard rgbaBytes[pixelOffset + 3] == 0 else {
        continue
      }

      foundTransparentPixel = true
      guard
        rgbaBytes[pixelOffset] == 0,
        rgbaBytes[pixelOffset + 1] == 0,
        rgbaBytes[pixelOffset + 2] == 0
      else {
        return false
      }
    }

    return foundTransparentPixel && cornerAlpha.allSatisfy { $0 == 0 }
  }

  var signature: String {
    let bounds = alphaBounds?.description ?? "empty"
    return "sha256=\(sha256) alpha=\(alphaPixelCount) bounds=\(bounds)"
  }

  private func alpha(x: Int, y: Int) -> UInt8 {
    rgbaBytes[(y * width + x) * 4 + 3]
  }
}

enum CPUVisualRendererError: Error {
  case imageSourceUnavailable(URL)
  case imageUnavailable(URL)
  case invalidPointSize(CGSize)
  case unsupportedScale(Int)
  case colorSpaceUnavailable
  case contextUnavailable
}

enum CPUVisualRenderer {
  static func render(
    imageURL: URL,
    pointSize: CGSize,
    scale: Int
  ) throws -> CPURenderedVisual {
    guard scale == 1 || scale == 2 else {
      throw CPUVisualRendererError.unsupportedScale(scale)
    }

    let scaledWidth = pointSize.width * CGFloat(scale)
    let scaledHeight = pointSize.height * CGFloat(scale)
    guard
      scaledWidth > 0,
      scaledHeight > 0,
      scaledWidth.rounded() == scaledWidth,
      scaledHeight.rounded() == scaledHeight
    else {
      throw CPUVisualRendererError.invalidPointSize(pointSize)
    }

    guard
      let source = CGImageSourceCreateWithURL(
        imageURL as CFURL,
        nil
      )
    else {
      throw CPUVisualRendererError.imageSourceUnavailable(imageURL)
    }
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      throw CPUVisualRendererError.imageUnavailable(imageURL)
    }
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw CPUVisualRendererError.colorSpaceUnavailable
    }

    let width = Int(scaledWidth)
    let height = Int(scaledHeight)
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

    let didRender = pixels.withUnsafeMutableBytes { bytes -> Bool in
      let bitmapInfo =
        CGBitmapInfo.byteOrder32Big.rawValue
        | CGImageAlphaInfo.premultipliedLast.rawValue
      guard
        let context = CGContext(
          data: bytes.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: bytesPerRow,
          space: colorSpace,
          bitmapInfo: bitmapInfo
        )
      else {
        return false
      }

      context.setBlendMode(.copy)
      context.interpolationQuality = .none
      context.draw(
        image,
        in: CGRect(x: 0, y: 0, width: width, height: height)
      )
      return true
    }
    guard didRender else {
      throw CPUVisualRendererError.contextUnavailable
    }

    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1
    var alphaPixelCount = 0

    for y in 0..<height {
      for x in 0..<width {
        let alpha = pixels[(y * width + x) * 4 + 3]
        guard alpha > 0 else {
          continue
        }

        alphaPixelCount += 1
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
      }
    }

    let alphaBounds =
      alphaPixelCount > 0
      ? VisualPixelBounds(
        minX: minX,
        minY: minY,
        maxX: maxX,
        maxY: maxY
      )
      : nil

    return CPURenderedVisual(
      width: width,
      height: height,
      rgbaBytes: pixels,
      alphaBounds: alphaBounds,
      alphaPixelCount: alphaPixelCount
    )
  }
}
