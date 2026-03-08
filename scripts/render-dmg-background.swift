import AppKit
import CoreImage
import Foundation

let outputWidth: CGFloat = 720
let outputHeight: CGFloat = 460
let canvasRect = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)

let titleRect = CGRect(x: 80, y: 322, width: 560, height: 54)
let subtitleRect = CGRect(x: 120, y: 288, width: 480, height: 30)
let arrowY: CGFloat = 180
let arrowStartX: CGFloat = 286
let arrowEndX: CGFloat = 434

guard CommandLine.arguments.count >= 2 else {
  fputs("usage: render-dmg-background.swift <output> [texture-image]\n", stderr)
  exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let textureURL = CommandLine.arguments.count >= 3 ? URL(fileURLWithPath: CommandLine.arguments[2]) : nil

guard
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(outputWidth),
    pixelsHigh: Int(outputHeight),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )
else {
  fputs("error: failed to create bitmap target\n", stderr)
  exit(1)
}

NSGraphicsContext.saveGraphicsState()

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
  fputs("error: failed to create graphics context\n", stderr)
  exit(1)
}

NSGraphicsContext.current = graphicsContext

guard let context = NSGraphicsContext.current?.cgContext else {
  fputs("error: failed to access graphics context\n", stderr)
  exit(1)
}

func drawBaseFill(in rect: CGRect) {
  NSColor(calibratedRed: 0.973, green: 0.961, blue: 0.941, alpha: 1.0).setFill()
  rect.fill()
}

func drawTexture(from url: URL, in rect: CGRect, context: CGContext) {
  guard
    let data = try? Data(contentsOf: url),
    let inputImage = CIImage(data: data)
  else {
    return
  }

  let ciContext = CIContext(options: nil)
  let blur = CIFilter(name: "CIGaussianBlur")
  blur?.setValue(inputImage, forKey: kCIInputImageKey)
  blur?.setValue(22.0, forKey: kCIInputRadiusKey)

  guard
    let blurredImage = blur?.outputImage?.cropped(to: inputImage.extent),
    let cgImage = ciContext.createCGImage(blurredImage, from: inputImage.extent)
  else {
    return
  }

  let sourceRect = inputImage.extent
  let targetAspect = rect.width / rect.height
  let sourceAspect = sourceRect.width / sourceRect.height

  var cropRect = sourceRect
  if sourceAspect > targetAspect {
    let cropWidth = sourceRect.height * targetAspect
    cropRect.origin.x += (sourceRect.width - cropWidth) / 2
    cropRect.size.width = cropWidth
  } else {
    let cropHeight = sourceRect.width / targetAspect
    cropRect.origin.y += (sourceRect.height - cropHeight) / 2
    cropRect.size.height = cropHeight
  }

  let blurredNSImage = NSImage(cgImage: cgImage, size: sourceRect.size)
  blurredNSImage.draw(in: rect, from: cropRect, operation: NSCompositingOperation.sourceOver, fraction: 0.24)

  NSColor(calibratedRed: 1.0, green: 0.995, blue: 0.985, alpha: 0.74).setFill()
  rect.fill()
}

func drawTopGlow(in rect: CGRect) {
  let gradient = NSGradient(
    colors: [
      NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.62),
      NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.10)
    ]
  )
  gradient?.draw(in: CGRect(x: rect.minX, y: rect.midY - 30, width: rect.width, height: rect.height / 2 + 30), angle: 90)
}

func drawTitle(in rect: CGRect) {
  let style = NSMutableParagraphStyle()
  style.alignment = .center

  let title = NSAttributedString(
    string: "Drag HoldToTalk to Applications",
    attributes: [
      .font: NSFont.systemFont(ofSize: 33, weight: .semibold),
      .foregroundColor: NSColor(calibratedRed: 0.173, green: 0.157, blue: 0.141, alpha: 1.0),
      .paragraphStyle: style
    ]
  )

  let subtitle = NSAttributedString(
    string: "Then open it from Applications.",
    attributes: [
      .font: NSFont.systemFont(ofSize: 17, weight: .regular),
      .foregroundColor: NSColor(calibratedRed: 0.345, green: 0.314, blue: 0.282, alpha: 0.88),
      .paragraphStyle: style
    ]
  )

  title.draw(in: titleRect)
  subtitle.draw(in: subtitleRect)
}

func drawArrow(in context: CGContext) {
  context.saveGState()
  context.setStrokeColor(NSColor(calibratedRed: 0.709, green: 0.661, blue: 0.588, alpha: 0.95).cgColor)
  context.setLineWidth(3.0)
  context.setLineCap(.round)
  context.setLineDash(phase: 0, lengths: [1.0, 9.0])
  context.move(to: CGPoint(x: arrowStartX, y: arrowY))
  context.addLine(to: CGPoint(x: arrowEndX, y: arrowY))
  context.strokePath()

  context.setLineDash(phase: 0, lengths: [])
  context.setLineWidth(4.0)
  context.move(to: CGPoint(x: arrowEndX, y: arrowY))
  context.addLine(to: CGPoint(x: arrowEndX - 18, y: arrowY + 12))
  context.move(to: CGPoint(x: arrowEndX, y: arrowY))
  context.addLine(to: CGPoint(x: arrowEndX - 18, y: arrowY - 12))
  context.strokePath()
  context.restoreGState()
}

drawBaseFill(in: canvasRect)

if let textureURL {
  drawTexture(from: textureURL, in: canvasRect, context: context)
}

drawTopGlow(in: canvasRect)
drawTitle(in: canvasRect)
drawArrow(in: context)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
  fputs("error: failed to encode PNG output\n", stderr)
  exit(1)
}

try pngData.write(to: outputURL)
