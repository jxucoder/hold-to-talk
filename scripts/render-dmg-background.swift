import AppKit
import CoreImage
import Foundation

let outputWidth: CGFloat = 720
let outputHeight: CGFloat = 460
let canvasRect = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)

let titleRect = CGRect(x: 70, y: 330, width: 580, height: 52)
let subtitleRect = CGRect(x: 90, y: 294, width: 540, height: 24)
let laneRect = CGRect(x: 72, y: 116, width: 576, height: 132)
let leftStepRect = CGRect(x: 108, y: 222, width: 160, height: 24)
let rightStepRect = CGRect(x: 452, y: 222, width: 170, height: 24)
let footerRect = CGRect(x: 150, y: 42, width: 420, height: 18)
let applicationsIconRect = CGRect(x: 469, y: 120, width: 126, height: 126)
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
  NSColor(calibratedRed: 0.978, green: 0.972, blue: 0.962, alpha: 1.0).setFill()
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
  blurredNSImage.draw(in: rect, from: cropRect, operation: NSCompositingOperation.sourceOver, fraction: 0.08)

  NSColor(calibratedRed: 1.0, green: 0.998, blue: 0.992, alpha: 0.90).setFill()
  rect.fill()
}

func drawTopGlow(in rect: CGRect) {
  let gradient = NSGradient(
    colors: [
      NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.52),
      NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.06)
    ]
  )
  gradient?.draw(in: CGRect(x: rect.minX, y: rect.midY - 30, width: rect.width, height: rect.height / 2 + 30), angle: 90)
}

func drawLane(in rect: CGRect) {
  let lanePath = NSBezierPath(roundedRect: laneRect, xRadius: 24, yRadius: 24)
  NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.68).setFill()
  lanePath.fill()

  NSColor(calibratedRed: 0.863, green: 0.835, blue: 0.788, alpha: 0.85).setStroke()
  lanePath.lineWidth = 1.0
  lanePath.stroke()
}

func drawApplicationsIcon() {
  let backgroundPath = NSBezierPath(roundedRect: applicationsIconRect.insetBy(dx: -6, dy: -6), xRadius: 22, yRadius: 22)
  NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.52).setFill()
  backgroundPath.fill()

  let applicationsIcon = NSWorkspace.shared.icon(forFile: "/Applications")
  applicationsIcon.size = NSSize(width: applicationsIconRect.width, height: applicationsIconRect.height)
  applicationsIcon.draw(
    in: applicationsIconRect,
    from: .zero,
    operation: .sourceOver,
    fraction: 0.92,
    respectFlipped: false,
    hints: [.interpolation: NSImageInterpolation.high]
  )
}

func drawTitle(in rect: CGRect) {
  let style = NSMutableParagraphStyle()
  style.alignment = .center

  let title = NSAttributedString(
    string: "Drag HoldToTalk to Applications",
    attributes: [
      .font: NSFont.systemFont(ofSize: 34, weight: .bold),
      .foregroundColor: NSColor(calibratedRed: 0.164, green: 0.148, blue: 0.132, alpha: 1.0),
      .paragraphStyle: style
    ]
  )

  let subtitle = NSAttributedString(
    string: "After the drag, open HoldToTalk from Applications.",
    attributes: [
      .font: NSFont.systemFont(ofSize: 17, weight: .medium),
      .foregroundColor: NSColor(calibratedRed: 0.314, green: 0.286, blue: 0.255, alpha: 0.92),
      .paragraphStyle: style
    ]
  )

  let leftStep = NSAttributedString(
    string: "1. Drag this app",
    attributes: [
      .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
      .foregroundColor: NSColor(calibratedRed: 0.396, green: 0.352, blue: 0.286, alpha: 0.96),
      .paragraphStyle: style
    ]
  )

  let rightStep = NSAttributedString(
    string: "2. Open it there",
    attributes: [
      .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
      .foregroundColor: NSColor(calibratedRed: 0.396, green: 0.352, blue: 0.286, alpha: 0.96),
      .paragraphStyle: style
    ]
  )

  let footer = NSAttributedString(
    string: "Do not open the copy inside this disk image.",
    attributes: [
      .font: NSFont.systemFont(ofSize: 13, weight: .medium),
      .foregroundColor: NSColor(calibratedRed: 0.427, green: 0.384, blue: 0.333, alpha: 0.88),
      .paragraphStyle: style
    ]
  )

  title.draw(in: titleRect)
  subtitle.draw(in: subtitleRect)
  leftStep.draw(in: leftStepRect)
  rightStep.draw(in: rightStepRect)
  footer.draw(in: footerRect)
}

func drawArrow(in context: CGContext) {
  context.saveGState()
  context.setStrokeColor(NSColor(calibratedRed: 0.709, green: 0.648, blue: 0.529, alpha: 1.0).cgColor)
  context.setLineWidth(4.0)
  context.setLineCap(.round)
  context.setLineDash(phase: 0, lengths: [])
  context.move(to: CGPoint(x: arrowStartX, y: arrowY))
  context.addLine(to: CGPoint(x: arrowEndX, y: arrowY))
  context.strokePath()

  context.setLineWidth(4.0)
  context.move(to: CGPoint(x: arrowEndX, y: arrowY))
  context.addLine(to: CGPoint(x: arrowEndX - 18, y: arrowY + 12))
  context.move(to: CGPoint(x: arrowEndX, y: arrowY))
  context.addLine(to: CGPoint(x: arrowEndX - 18, y: arrowY - 12))
  context.strokePath()
  context.restoreGState()
}

drawBaseFill(in: canvasRect)
drawTopGlow(in: canvasRect)
drawLane(in: canvasRect)
drawApplicationsIcon()
drawTitle(in: canvasRect)
drawArrow(in: context)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
  fputs("error: failed to encode PNG output\n", stderr)
  exit(1)
}

try pngData.write(to: outputURL)
