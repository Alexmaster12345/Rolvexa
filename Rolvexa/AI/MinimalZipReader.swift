import Foundation
import Compression

/// Reads a single named entry out of a ZIP archive — the counterpart to `MinimalZipWriter`.
/// Unlike this app's own writer (which only ever produces "stored"/uncompressed entries), real
/// `.docx` files exported from Word, Pages, or Google Docs almost always use DEFLATE
/// compression, so both methods are supported here.
enum MinimalZipReader {
    static func extract(entryName: String, from archive: Data) -> Data? {
        let bytes = [UInt8](archive)
        // Scans local file headers directly rather than parsing the central directory — every
        // local header already carries the name/size/method fields needed here, and this
        // avoids a second pass to locate the end-of-central-directory record first.
        var offset = 0
        while offset + 30 <= bytes.count {
            guard readUInt32LE(bytes, offset) == 0x0403_4b50 else { break } // local file header signature
            let method = readUInt16LE(bytes, offset + 8)
            let compressedSize = Int(readUInt32LE(bytes, offset + 18))
            let uncompressedSize = Int(readUInt32LE(bytes, offset + 22))
            let nameLength = Int(readUInt16LE(bytes, offset + 26))
            let extraLength = Int(readUInt16LE(bytes, offset + 28))
            let nameStart = offset + 30
            guard nameLength >= 0, nameStart + nameLength <= bytes.count else { break }
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            let dataStart = nameStart + nameLength + extraLength
            guard compressedSize >= 0, dataStart + compressedSize <= bytes.count else { break }
            let entryData = Data(bytes[dataStart..<(dataStart + compressedSize)])

            if name == entryName {
                switch method {
                case 0: return entryData
                case 8: return inflate(entryData, expectedSize: uncompressedSize)
                default: return nil
                }
            }
            offset = dataStart + compressedSize
        }
        return nil
    }

    private static func readUInt16LE(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }

    /// ZIP's "deflated" method is raw DEFLATE (RFC 1951, no zlib/gzip header) — which is exactly
    /// what Apple's `COMPRESSION_ZLIB` algorithm identifier implements despite the name.
    private static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        var destination = [UInt8](repeating: 0, count: expectedSize)
        let sourceBytes = [UInt8](data)
        guard !sourceBytes.isEmpty else { return nil }
        let decodedCount = destination.withUnsafeMutableBufferPointer { destBuffer -> Int in
            sourceBytes.withUnsafeBufferPointer { srcBuffer -> Int in
                guard let destBase = destBuffer.baseAddress, let srcBase = srcBuffer.baseAddress else { return 0 }
                return compression_decode_buffer(
                    destBase, expectedSize,
                    srcBase, sourceBytes.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount == expectedSize else { return nil }
        return Data(destination)
    }
}
