import AppKit
import CoreImage
import Foundation
import Vision

struct ProcessedImage {
    /// Trimmed, padded PNG with a transparent background (when removal ran).
    var png: Data
    var dominantColor: RGB?
    var categoryGuess: Category?
    var backgroundRemoved: Bool
}

/// Turns a raw photo into a clean garment cut-out using Apple's Vision
/// subject lifting (the same model behind "Copy Subject" in Photos).
enum ImageProcessor {
    enum Failure: LocalizedError {
        case unreadable
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: return "The file isn't an image Wardrobe can read."
            case .encodeFailed: return "The cut-out couldn't be saved."
            }
        }
    }

    /// Longest side of the stored image, in pixels.
    static let maxStoredSide: CGFloat = 1200

    /// `crop` is a region in normalized, top-left-origin coordinates to keep
    /// before lifting the subject, such as the garment on a model.
    static func process(imageData: Data, removeBackground: Bool, crop: CGRect? = nil) async throws -> ProcessedImage {
        try await Task.detached(priority: .userInitiated) {
            try processSync(imageData: imageData, removeBackground: removeBackground, crop: crop)
        }.value
    }

    /// What a product photo shows: just the garment, or a person wearing it.
    struct PhotoCheck: Sendable {
        var hasPerson: Bool
        /// Body joints in normalized, top-left-origin coordinates.
        var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        /// The piece's main color: the lifted subject's, or for a model photo,
        /// the color where the piece sits on the body.
        var pieceColor: RGB?
        /// The lifted subject sits clear of the photo's edges, as a product shot
        /// does. A close-up of the fabric or a pocket fills the frame instead.
        var isolated = false
        /// How much of the subject is its main color. A row of the piece in
        /// every color scores low (0.4 to 0.65 on Uniqlo's), a single piece
        /// high (0.95 and up).
        var colorPurity = 0.0

        /// A photo of just the piece, whole and on its own.
        var isProductShot: Bool { !hasPerson && isolated && colorPurity >= 0.75 }

        /// Where a piece of `category` sits on the person, padded a little,
        /// or nil when the pose doesn't show enough of the body to tell.
        func garmentRegion(for category: Category) -> CGRect? {
            func ys(_ names: [VNHumanBodyPoseObservation.JointName]) -> [CGFloat] { names.compactMap { joints[$0]?.y } }
            func xs(_ names: [VNHumanBodyPoseObservation.JointName]) -> [CGFloat] { names.compactMap { joints[$0]?.x } }
            let shoulders = ys([.leftShoulder, .rightShoulder, .neck])
            let hips = ys([.leftHip, .rightHip, .root])
            let knees = ys([.leftKnee, .rightKnee])
            let ankles = ys([.leftAnkle, .rightAnkle])
            let arms = xs([.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist, .leftHip, .rightHip])
            let legs = xs([.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle])

            var top: CGFloat, bottom: CGFloat, xRange: [CGFloat], padX: CGFloat
            switch category {
            case .top, .outerwear:
                guard let s = shoulders.min(), let h = hips.max(), !arms.isEmpty else { return nil }
                top = s - 0.05
                bottom = h + (category == .outerwear ? 0.14 : 0.07)
                xRange = arms; padX = 0.07
            case .dress:
                guard let s = shoulders.min(), let low = (ankles + knees).max(), !arms.isEmpty else { return nil }
                top = s - 0.05; bottom = low + 0.04
                xRange = arms + legs; padX = 0.08
            case .bottom:
                guard let h = hips.min(), let low = (ankles.isEmpty ? knees.map { $0 + 0.2 } : ankles).max(), !legs.isEmpty
                else { return nil }
                top = h - 0.03; bottom = low + 0.05
                xRange = legs; padX = 0.1
            case .shoes:
                guard let a = ankles.min(), let aMax = ankles.max(), !legs.isEmpty else { return nil }
                top = a - 0.05; bottom = aMax + 0.1
                xRange = xs([.leftAnkle, .rightAnkle]); padX = 0.12
            case .accessory:
                return nil
            }
            guard let minX = xRange.min(), let maxX = xRange.max() else { return nil }
            let rect = CGRect(x: minX - padX, y: top, width: maxX - minX + padX * 2, height: bottom - top)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            return rect.width > 0.1 && rect.height > 0.08 ? rect : nil
        }
    }

    /// Looks for a person in the photo (a face, a body, or enough body joints:
    /// a legs-only shot of trousers still counts), and measures the piece's
    /// color and whether it stands alone, assuming it's a `category`.
    static func check(imageData: Data, category: Category) async -> PhotoCheck? {
        await Task.detached(priority: .userInitiated) { () -> PhotoCheck? in
            guard let image = CIImage(data: imageData, options: [.applyOrientationProperty: true]) else { return nil }
            let faces = VNDetectFaceRectanglesRequest()
            let humans = VNDetectHumanRectanglesRequest()
            humans.upperBodyOnly = false
            let pose = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            try? handler.perform([faces, humans, pose])

            var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
            if let body = pose.results?.max(by: { $0.confidence < $1.confidence }),
               let points = try? body.recognizedPoints(.all) {
                for (name, point) in points where point.confidence > 0.25 {
                    joints[name] = CGPoint(x: point.location.x, y: 1 - point.location.y)
                }
            }
            let hasFace = faces.results?.contains { $0.confidence > 0.6 } ?? false
            let hasBody = humans.results?.contains { $0.confidence > 0.6 } ?? false
            var result = PhotoCheck(hasPerson: hasFace || hasBody || joints.count >= 5, joints: joints)

            // Color work runs on a small copy; it only needs a rough answer.
            var small = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            let s = min(1, 512 / max(small.extent.width, small.extent.height))
            small = small.transformed(by: CGAffineTransform(scaleX: s, y: s))

            if result.hasPerson {
                guard let region = result.garmentRegion(for: category),
                      let cg = ciContext.createCGImage(small, from: small.extent), let bitmap = Bitmap(cg) else { return result }
                // The middle of the region, clear of arms and background.
                let w = CGFloat(bitmap.width), h = CGFloat(bitmap.height)
                let core = CGRect(x: (region.midX - region.width * 0.18) * w, y: (region.minY + region.height * 0.3) * h,
                                  width: region.width * 0.36 * w, height: region.height * 0.4 * h).integral
                result.pieceColor = bitmap.dominantColor(in: core, requireOpaque: false)
                return result
            }

            guard let cutout = liftSubject(from: small),
                  let cg = ciContext.createCGImage(cutout, from: small.extent), let bitmap = Bitmap(cg),
                  let bounds = bitmap.opaqueBounds() else { return result }
            let margin = CGFloat(min(bitmap.width, bitmap.height)) * 0.02
            result.isolated = bounds.minX > margin && bounds.minY > margin
                && bounds.maxX < CGFloat(bitmap.width) - margin && bounds.maxY < CGFloat(bitmap.height) - margin
            if let color = bitmap.dominantColor(in: bounds, requireOpaque: true) {
                result.pieceColor = color
                result.colorPurity = bitmap.share(near: color, in: bounds)
            }
            return result
        }.value
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func processSync(imageData: Data, removeBackground: Bool, crop: CGRect? = nil) throws -> ProcessedImage {
        guard var image = CIImage(data: imageData, options: [.applyOrientationProperty: true]) else {
            throw Failure.unreadable
        }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        if let crop {
            // Core Image's origin is bottom-left; `crop` is top-left.
            let e = image.extent
            let rect = CGRect(x: crop.minX * e.width, y: (1 - crop.maxY) * e.height,
                              width: crop.width * e.width, height: crop.height * e.height).integral
            image = image.cropped(to: rect)
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        }

        // Work at a sensible size; huge camera photos slow Vision down for no gain.
        let workingSide: CGFloat = 2048
        let longest = max(image.extent.width, image.extent.height)
        if longest > workingSide {
            let s = workingSide / longest
            image = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }

        let category = classify(image)

        var removed = false
        if removeBackground, let cutout = liftSubject(from: image) {
            image = cutout
            removed = true
        }

        guard let cg = ciContext.createCGImage(image, from: image.extent) else { throw Failure.unreadable }
        guard let bitmap = Bitmap(cg) else { throw Failure.unreadable }

        let bounds = removed ? (bitmap.opaqueBounds() ?? bitmap.fullRect) : bitmap.fullRect
        let color = bitmap.dominantColor(in: removed ? bounds : bitmap.centerRect(fraction: 0.5), requireOpaque: removed)

        guard let cropped = cg.cropping(to: bounds),
              let framed = frame(cropped, padded: removed),
              let png = NSBitmapImageRep(cgImage: framed).representation(using: .png, properties: [:])
        else { throw Failure.encodeFailed }

        return ProcessedImage(png: png, dominantColor: color, categoryGuess: category, backgroundRemoved: removed)
    }

    // MARK: Vision

    /// Returns the image with everything but the foreground subject(s) made transparent.
    private static func liftSubject(from image: CIImage) -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
            let maskBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            let mask = CIImage(cvPixelBuffer: maskBuffer)
            return image.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: mask,
            ])
        } catch {
            return nil
        }
    }

    /// A rough guess at the category from Vision's built-in image labels.
    private static func classify(_ image: CIImage) -> Category? {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results else { return nil }
        let rules: [(Category, [String])] = [
            (.shoes, ["shoe", "sneaker", "boot", "sandal", "footwear", "loafer", "heel"]),
            (.dress, ["dress", "gown", "jumpsuit"]),
            (.outerwear, ["coat", "jacket", "parka", "blazer", "vest"]),
            (.bottom, ["jeans", "pants", "trouser", "shorts", "skirt", "denim"]),
            (.accessory, ["bag", "handbag", "purse", "backpack", "hat", "cap", "scarf", "belt", "sunglasses",
                          "eyeglasses", "watch", "jewelry", "necklace", "tie"]),
            (.top, ["shirt", "sweater", "sweatshirt", "hoodie", "blouse", "top", "jersey", "cardigan"]),
        ]
        for obs in observations.prefix(40) where obs.confidence > 0.08 {
            let id = obs.identifier.lowercased()
            for (category, words) in rules where words.contains(where: { id.contains($0) }) {
                return category
            }
        }
        return nil
    }

    // MARK: Framing

    /// Scales the crop down to the stored size and, for cut-outs, adds a little
    /// transparent breathing room so drop shadows aren't clipped.
    private static func frame(_ image: CGImage, padded: Bool) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let scale = min(1, maxStoredSide / max(w, h))
        let pad: CGFloat = padded ? max(w, h) * scale * 0.04 : 0
        let outW = Int((w * scale + pad * 2).rounded()), outH = Int((h * scale + pad * 2).rounded())
        guard let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: pad, y: pad, width: w * scale, height: h * scale))
        return ctx.makeImage()
    }
}

/// An RGBA8 copy of an image for pixel sampling. Row 0 is the top of the image,
/// matching `CGImage.cropping(to:)`.
private struct Bitmap {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(_ image: CGImage) {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        width = w
        height = h
        pixels = buffer
    }

    var fullRect: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    func centerRect(fraction: CGFloat) -> CGRect {
        let w = CGFloat(width) * fraction, h = CGFloat(height) * fraction
        return CGRect(x: (CGFloat(width) - w) / 2, y: (CGFloat(height) - h) / 2, width: w, height: h).integral
    }

    private func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }

    /// The smallest rectangle holding all clearly visible pixels.
    func opaqueBounds(threshold: UInt8 = 24) -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        let step = max(1, min(width, height) / 600)
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) where alpha(x, y) > threshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let x0 = max(0, minX - step), y0 = max(0, minY - step)
        let x1 = min(width, maxX + step + 1), y1 = min(height, maxY + step + 1)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// The share of opaque pixels in a region within a small color distance of `color`.
    func share(near color: RGB, in rect: CGRect, within limit: Double = 18) -> Double {
        let r = rect.intersection(fullRect)
        guard !r.isEmpty else { return 0 }
        let step = max(1, Int(max(r.width, r.height)) / 120)
        var near = 0, total = 0
        for y in stride(from: Int(r.minY), to: Int(r.maxY), by: step) {
            for x in stride(from: Int(r.minX), to: Int(r.maxX), by: step) {
                let i = (y * width + x) * 4
                let a = Double(pixels[i + 3])
                guard a >= 220 else { continue }
                let rgb = RGB(r: Double(pixels[i]) / a, g: Double(pixels[i + 1]) / a, b: Double(pixels[i + 2]) / a)
                total += 1
                if rgb.distance(to: color) < limit { near += 1 }
            }
        }
        return total == 0 ? 0 : Double(near) / Double(total)
    }

    /// The most common color in a region, found by bucketing pixels and
    /// averaging the busiest bucket. Robust to stripes, prints and shadows.
    func dominantColor(in rect: CGRect, requireOpaque: Bool) -> RGB? {
        let r = rect.intersection(fullRect)
        guard !r.isEmpty else { return nil }
        struct Acc { var n = 0; var r = 0.0; var g = 0.0; var b = 0.0 }
        var buckets: [Int: Acc] = [:]
        let step = max(1, Int(max(r.width, r.height)) / 160)
        for y in stride(from: Int(r.minY), to: Int(r.maxY), by: step) {
            for x in stride(from: Int(r.minX), to: Int(r.maxX), by: step) {
                let i = (y * width + x) * 4
                let a = Double(pixels[i + 3])
                if requireOpaque && a < 220 { continue }
                guard a > 0 else { continue }
                // Un-premultiply.
                let pr = Double(pixels[i]) / a, pg = Double(pixels[i + 1]) / a, pb = Double(pixels[i + 2]) / a
                let key = (Int(pr * 7.99) << 6) | (Int(pg * 7.99) << 3) | Int(pb * 7.99)
                var acc = buckets[key, default: Acc()]
                acc.n += 1; acc.r += pr; acc.g += pg; acc.b += pb
                buckets[key] = acc
            }
        }
        guard let best = buckets.values.max(by: { $0.n < $1.n }), best.n > 0 else { return nil }
        let n = Double(best.n)
        return RGB(r: best.r / n, g: best.g / n, b: best.b / n)
    }
}
