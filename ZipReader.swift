import Foundation

/// 极简 ZIP 读取器，依赖系统 zlib，够解 EPUB（store/deflate）。
final class ZipReader {
    struct Entry {
        let name: String
        let localHeaderOffset: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let compressionMethod: UInt16
    }

    private let data: Data
    private var entries: [String: Entry] = [:]

    init(url: URL) throws {
        self.data = try Data(contentsOf: url)
        try parseCentralDirectory()
    }

    func read(_ path: String) -> Data? {
        guard let e = entries[path] else { return nil }
        return extract(e)
    }

    private func parseCentralDirectory() throws {
        let eocdSig: UInt32 = 0x06054b50
        let n = data.count
        guard n > 22 else { throw BookParseError.unreadable }
        var eocdOffset: Int?
        let limit = max(0, n - 22 - 65535)
        var i = n - 22
        while i >= limit {
            if readU32(i) == eocdSig { eocdOffset = i; break }
            i -= 1
        }
        guard let eocd = eocdOffset else { throw BookParseError.unreadable }

        let cdCount = Int(readU16(eocd + 10))
        let cdOffset = Int(readU32(eocd + 16))
        var p = cdOffset
        let cdSig: UInt32 = 0x02014b50
        for _ in 0..<cdCount {
            guard p + 46 <= n, readU32(p) == cdSig else { break }
            let method = readU16(p + 10)
            let compSize = readU32(p + 20)
            let uncompSize = readU32(p + 24)
            let nameLen = Int(readU16(p + 28))
            let extraLen = Int(readU16(p + 30))
            let commentLen = Int(readU16(p + 32))
            let localOffset = readU32(p + 42)
            let name = String(data: data.subdata(in: (p + 46)..<(p + 46 + nameLen)),
                              encoding: .utf8) ?? ""
            if !name.isEmpty {
                entries[name] = Entry(name: name,
                                      localHeaderOffset: localOffset,
                                      compressedSize: compSize,
                                      uncompressedSize: uncompSize,
                                      compressionMethod: method)
            }
            p += 46 + nameLen + extraLen + commentLen
        }
    }

    private func extract(_ e: Entry) -> Data? {
        let lh = Int(e.localHeaderOffset)
        guard lh + 30 <= data.count, readU32(lh) == 0x04034b50 else { return nil }
        let nameLen = Int(readU16(lh + 26))
        let extraLen = Int(readU16(lh + 28))
        let start = lh + 30 + nameLen + extraLen
        let end = start + Int(e.compressedSize)
        guard end <= data.count else { return nil }
        let raw = data.subdata(in: start..<end)

        switch e.compressionMethod {
        case 0: return raw
        case 8: return inflate(raw, expectedSize: Int(e.uncompressedSize))
        default: return nil
        }
    }

    private func inflate(_ input: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        var out = Data(count: expectedSize)
        var outLen = expectedSize
        let ok = input.withUnsafeBytes { inPtr -> Bool in
            guard let inBase = inPtr.bindMemory(to: UInt8.self).baseAddress else { return false }
            return out.withUnsafeMutableBytes { outPtr -> Bool in
                guard let outBase = outPtr.bindMemory(to: UInt8.self).baseAddress else { return false }
                var strm = z_stream()
                strm.next_in = UnsafeMutablePointer<Bytef>(mutating: inBase)
                strm.avail_in = uInt(input.count)
                strm.next_out = outBase
                strm.avail_out = uInt(outLen)
                guard inflateInit2_(&strm, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return false }
                let r = inflate(&strm, Z_FINISH)
                inflateEnd(&strm)
                outLen = Int(strm.total_out)
                return r == Z_STREAM_END
            }
        }
        guard ok else { return nil }
        return out.prefix(outLen)
    }

    private func readU16(_ offset: Int) -> UInt16 {
        data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }
    }
    private func readU32(_ offset: Int) -> UInt32 {
        data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
    }
}
