import AppKit
import CoreImage
import SwiftUI

/// The colour an album cover is remembered by, used to tint the island while its song plays.
enum ArtworkAccent {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// Average colour of the cover, pushed towards vivid so it still glows on black.
    /// Nil for covers that are close to grey, where the user's own palette looks better.
    static func color(from image: NSImage) -> Color? {
        guard let data = image.tiffRepresentation,
              let input = CIImage(data: data),
              let average = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: input,
                  kCIInputExtentKey: CIVector(cgRect: input.extent),
              ])?.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)

        let base = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                           blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        guard saturation > 0.12 else { return nil }

        return Color(nsColor: NSColor(hue: hue,
                                      saturation: min(1, saturation * 1.3 + 0.1),
                                      brightness: max(brightness, 0.85),
                                      alpha: 1))
    }

    /// A neighbour on the colour wheel, so a two-colour glow has some movement in it.
    static func companion(of color: Color) -> Color {
        let base = NSColor(color).usingColorSpace(.sRGB) ?? .white
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        let shifted = (hue + 0.09).truncatingRemainder(dividingBy: 1)
        return Color(nsColor: NSColor(hue: shifted, saturation: saturation * 0.8,
                                      brightness: 1, alpha: 1))
    }

    /// Up to three colours the cover is made of, most prominent first: the cover is shrunk
    /// to a few hundred pixels and its vivid ones are grouped by hue. Nil for covers with
    /// nothing vivid in them, where the user's own palette looks better.
    static func palette(from image: NSImage) -> [Color]? {
        let side = 20
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Twelve hue buckets, each weighted by how vivid and bright its pixels are, so a
        // small bright accent is not drowned by a large dull background.
        struct Bucket { var weight = 0.0; var hue = 0.0; var saturation = 0.0; var brightness = 0.0 }
        var buckets = [Bucket](repeating: Bucket(), count: 12)

        for index in 0..<(side * side) {
            let color = NSColor(red: CGFloat(pixels[index * 4]) / 255,
                                green: CGFloat(pixels[index * 4 + 1]) / 255,
                                blue: CGFloat(pixels[index * 4 + 2]) / 255, alpha: 1)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
            guard saturation > 0.2, brightness > 0.25 else { continue }

            let weight = Double(saturation * brightness)
            let slot = min(Int(hue * 12), 11)
            buckets[slot].weight += weight
            buckets[slot].hue += Double(hue) * weight
            buckets[slot].saturation += Double(saturation) * weight
            buckets[slot].brightness += Double(brightness) * weight
        }

        var chosen: [Bucket] = []
        for bucket in buckets.sorted(by: { $0.weight > $1.weight }) where bucket.weight > 0.4 {
            let hue = bucket.hue / bucket.weight
            // Neighbouring buckets are one colour to the eye, so require a visible gap.
            let distinct = chosen.allSatisfy {
                let gap = abs($0.hue / $0.weight - hue)
                return min(gap, 1 - gap) > 0.1
            }
            if distinct { chosen.append(bucket) }
            if chosen.count == 3 { break }
        }
        guard !chosen.isEmpty else { return nil }

        return chosen.map {
            Color(nsColor: NSColor(hue: CGFloat($0.hue / $0.weight),
                                   saturation: min(1, CGFloat($0.saturation / $0.weight) * 1.2 + 0.1),
                                   brightness: max(CGFloat($0.brightness / $0.weight), 0.9),
                                   alpha: 1))
        }
    }
}
