import CoreGraphics
import Foundation
import zlib

// Lossy PNG: reduces an image to a palette of at most 256 colours (median
// cut, refined by k-means, Floyd-Steinberg dithering) and writes an 8-bit
// palette PNG with transparency. Flat areas whose colours land in the
// palette stay exact; only gradients and photos get dithered. ImageIO can't
// write palette PNGs with alpha, hence the hand-written encoder
enum PngQuantizer {
    // Palette size for a quality setting: 100% keeps truecolour (nil)
    static func colorCount(forQuality quality: Double) -> Int? {
        guard quality < 0.99 else { return nil }
        let t = max(0, min(1, (quality - 0.1) / 0.89))
        return Int((16 + 240 * t).rounded())
    }

    // 5 bits per colour channel, 4 for alpha: the histogram and lookup key
    private static let keyCount = 1 << 19

    private static func key(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Int {
        (r >> 3) << 14 | (g >> 3) << 9 | (b >> 3) << 4 | (a >> 4)
    }

    static func encode(_ image: CGImage, colors: Int, dpi: (x: Double, y: Double)?) throws -> Data {
        let width = image.width, height = image.height
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let raw = context.data else { throw ConversionError.failedToEncodeImage(.png) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = UnsafeMutableBufferPointer(start: raw.bindMemory(to: UInt8.self, capacity: width * height * 4), count: width * height * 4)

        let palette = buildPalette(pixels, colors: max(2, min(256, colors)))
        let indices = mapPixels(pixels, width: width, height: height, palette: palette)
        return writePNG(width: width, height: height, palette: palette, indices: indices, iccData: space.copyICCData() as Data?, dpi: dpi)
    }

    // MARK: - Palette

    private struct Bucket {
        var r: Double, g: Double, b: Double, a: Double
        var count: Double
    }

    private static func buildPalette(_ pixels: UnsafeMutableBufferPointer<UInt8>, colors: Int) -> [[Double]] {
        // Histogram with per-bucket colour sums, so bucket means are exact
        var counts = [Int](repeating: 0, count: keyCount)
        var sums = [Int](repeating: 0, count: keyCount * 4)
        var i = 0
        while i < pixels.count {
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2]), a = Int(pixels[i + 3])
            let k = key(r, g, b, a)
            counts[k] += 1
            sums[k * 4] += r; sums[k * 4 + 1] += g; sums[k * 4 + 2] += b; sums[k * 4 + 3] += a
            i += 4
        }
        var buckets: [Bucket] = []
        for k in 0..<keyCount where counts[k] > 0 {
            let n = Double(counts[k])
            buckets.append(Bucket(r: Double(sums[k * 4]) / n, g: Double(sums[k * 4 + 1]) / n,
                                  b: Double(sums[k * 4 + 2]) / n, a: Double(sums[k * 4 + 3]) / n, count: n))
        }

        // Median cut: split the box with the widest weighted spread at its
        // weighted median until the palette is full
        var boxes: [[Int]] = [Array(buckets.indices)]
        func channel(_ bucket: Bucket, _ c: Int) -> Double {
            switch c { case 0: bucket.r; case 1: bucket.g; case 2: bucket.b; default: bucket.a * 2 }
        }
        while boxes.count < colors {
            var bestBox = -1, bestChannel = 0
            var bestScore = 0.0
            for (index, box) in boxes.enumerated() where box.count > 1 {
                var total = 0.0
                for b in box { total += buckets[b].count }
                for c in 0..<4 {
                    var low = Double.greatestFiniteMagnitude, high = -low
                    for b in box {
                        let v = channel(buckets[b], c)
                        low = min(low, v); high = max(high, v)
                    }
                    let score = (high - low) * total.squareRoot()
                    if score > bestScore { bestScore = score; bestBox = index; bestChannel = c }
                }
            }
            guard bestBox >= 0 else { break }
            let sorted = boxes[bestBox].sorted { channel(buckets[$0], bestChannel) < channel(buckets[$1], bestChannel) }
            let half = sorted.reduce(0.0) { $0 + buckets[$1].count } / 2
            var running = 0.0
            var cut = 1
            for (position, b) in sorted.enumerated() {
                running += buckets[b].count
                if running >= half { cut = max(1, min(sorted.count - 1, position + 1)); break }
            }
            boxes[bestBox] = Array(sorted[..<cut])
            boxes.append(Array(sorted[cut...]))
        }

        var palette = boxes.map { mean(of: $0, in: buckets) }

        // K-means refinement over the buckets
        for _ in 0..<3 {
            var accum = [[Double]](repeating: [0, 0, 0, 0, 0], count: palette.count)
            for bucket in buckets {
                let p = nearest([bucket.r, bucket.g, bucket.b, bucket.a], in: palette)
                accum[p][0] += bucket.r * bucket.count
                accum[p][1] += bucket.g * bucket.count
                accum[p][2] += bucket.b * bucket.count
                accum[p][3] += bucket.a * bucket.count
                accum[p][4] += bucket.count
            }
            for p in palette.indices where accum[p][4] > 0 {
                let n = accum[p][4]
                palette[p] = [accum[p][0] / n, accum[p][1] / n, accum[p][2] / n, accum[p][3] / n]
            }
        }

        // Snap near-opaque and near-clear entries, so opaque pixels never
        // pick up faint transparency
        return palette.map { entry in
            var e = entry
            if e[3] >= 250 { e[3] = 255 } else if e[3] <= 5 { e = [0, 0, 0, 0] }
            return e
        }
    }

    private static func mean(of box: [Int], in buckets: [Bucket]) -> [Double] {
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0, n = 0.0
        for index in box {
            let bucket = buckets[index]
            r += bucket.r * bucket.count; g += bucket.g * bucket.count
            b += bucket.b * bucket.count; a += bucket.a * bucket.count
            n += bucket.count
        }
        return [r / n, g / n, b / n, a / n]
    }

    // Alpha counts double: a wrong alpha shows more than a slightly wrong hue
    private static func nearest(_ c: [Double], in palette: [[Double]]) -> Int {
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, p) in palette.enumerated() {
            let dr = c[0] - p[0], dg = c[1] - p[1], db = c[2] - p[2], da = (c[3] - p[3]) * 2
            let distance = dr * dr + dg * dg + db * db + da * da
            if distance < bestDistance { bestDistance = distance; best = index }
        }
        return best
    }

    // MARK: - Mapping

    // Floyd-Steinberg at 3/4 strength: smooth gradients without the grain
    // full-strength dithering leaves in flat areas. Alpha is not diffused
    private static func mapPixels(_ pixels: UnsafeMutableBufferPointer<UInt8>, width: Int, height: Int, palette: [[Double]]) -> [UInt8] {
        var indices = [UInt8](repeating: 0, count: width * height)
        var cache = [Int16](repeating: -1, count: keyCount)
        var current = [Double](repeating: 0, count: (width + 2) * 3)
        var next = [Double](repeating: 0, count: (width + 2) * 3)
        let strength = 0.75

        for y in 0..<height {
            for x in 0..<width {
                let p = (y * width + x) * 4
                let e = (x + 1) * 3
                let a = Double(pixels[p + 3])
                // Premultiplied colour can't exceed its alpha
                let r = max(0, min(a, Double(pixels[p]) + current[e]))
                let g = max(0, min(a, Double(pixels[p + 1]) + current[e + 1]))
                let b = max(0, min(a, Double(pixels[p + 2]) + current[e + 2]))

                let k = key(Int(r), Int(g), Int(b), Int(a))
                var index = Int(cache[k])
                if index < 0 {
                    index = nearest([r, g, b, a], in: palette)
                    cache[k] = Int16(index)
                }
                indices[y * width + x] = UInt8(index)

                let chosen = palette[index]
                let errors = ((r - chosen[0]) * strength, (g - chosen[1]) * strength, (b - chosen[2]) * strength)
                for (c, error) in [errors.0, errors.1, errors.2].enumerated() where error != 0 {
                    current[e + 3 + c] += error * 7 / 16
                    next[e - 3 + c] += error * 3 / 16
                    next[e + c] += error * 5 / 16
                    next[e + 3 + c] += error * 1 / 16
                }
            }
            swap(&current, &next)
            for i in next.indices { next[i] = 0 }
        }
        return indices
    }

    // MARK: - PNG writer

    private static func writePNG(width: Int, height: Int, palette: [[Double]], indices: [UInt8], iccData: Data?, dpi: (x: Double, y: Double)?) -> Data {
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        var header = Data()
        header.appendBigEndian(UInt32(width))
        header.appendBigEndian(UInt32(height))
        header.append(contentsOf: [8, 3, 0, 0, 0]) // 8-bit, palette, deflate, no filter, no interlace
        png.appendChunk("IHDR", header)

        if let iccData, let compressed = deflate(iccData) {
            var icc = Data("ICC Profile".utf8)
            icc.append(contentsOf: [0, 0]) // name terminator, compression method
            icc.append(compressed)
            png.appendChunk("iCCP", icc)
        }

        if let dpi {
            var physical = Data()
            physical.appendBigEndian(UInt32((dpi.x / 0.0254).rounded()))
            physical.appendBigEndian(UInt32((dpi.y / 0.0254).rounded()))
            physical.append(1) // unit: metre
            png.appendChunk("pHYs", physical)
        }

        // Palette entries are premultiplied; PNG stores straight colour
        var colours = Data(), alphas = Data()
        for entry in palette {
            let a = entry[3]
            for c in 0..<3 {
                let straight = a > 0 ? min(255, entry[c] * 255 / a) : 0
                colours.append(UInt8(straight.rounded()))
            }
            alphas.append(UInt8(a.rounded()))
        }
        png.appendChunk("PLTE", colours)
        if alphas.contains(where: { $0 < 255 }) {
            png.appendChunk("tRNS", alphas)
        }

        // Every row: filter type 0, then the palette indices
        var rows = Data(capacity: (width + 1) * height)
        indices.withUnsafeBufferPointer { buffer in
            for y in 0..<height {
                rows.append(0)
                rows.append(contentsOf: buffer[(y * width)..<((y + 1) * width)])
            }
        }
        png.appendChunk("IDAT", deflate(rows) ?? Data())
        png.appendChunk("IEND", Data())
        return png
    }

    private static func deflate(_ data: Data) -> Data? {
        var length = compressBound(uLong(data.count))
        var output = Data(count: Int(length))
        let status = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                compress2(out.bindMemory(to: Bytef.self).baseAddress, &length,
                          input.bindMemory(to: Bytef.self).baseAddress, uLong(data.count), 9)
            }
        }
        guard status == Z_OK else { return nil }
        return output.prefix(Int(length))
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendChunk(_ type: String, _ body: Data) {
        appendBigEndian(UInt32(body.count))
        let typed = Data(type.utf8) + body
        append(typed)
        let crc = typed.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(typed.count)) }
        appendBigEndian(UInt32(crc))
    }
}
