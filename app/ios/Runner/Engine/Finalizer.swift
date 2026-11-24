import AVFoundation

/// ADTS framing for the crash-safe `audio.aac.part` stream: every AAC frame carries its own
/// 7-byte header, so a file cut off by a crash is readable up to its last whole frame.
/// Same layout as the Android engine (Adts.kt).
enum Adts {
  static let header = 7
  static let rates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]

  /// Header for one AAC-LC frame whose payload is `payload` bytes (no CRC).
  static func frameHeader(payload: Int, sampleRate: Int, channels: Int) -> [UInt8] {
    let len = payload + header
    let idx = rates.firstIndex(of: sampleRate) ?? 3
    return [
      0xFF,
      0xF1,  // MPEG-4, layer 0, no CRC
      UInt8((1 << 6) | (idx << 2) | (channels >> 2)),  // profile LC (2-1)
      UInt8(((channels & 3) << 6) | (len >> 11)),
      UInt8((len >> 3) & 0xFF),
      UInt8(((len & 7) << 5) | 0x1F),
      0xFC,
    ]
  }

  /// Copies the whole frames of `part` into `out` and returns how many there were; stops at the
  /// first damaged or truncated frame (a crash can cut the last one). Writes nothing for zero.
  static func copyWholeFrames(from part: URL, to out: URL) throws -> Int {
    let data = try Data(contentsOf: part, options: .mappedIfSafe)
    var count = 0
    let end: Int = data.withUnsafeBytes { p in
      var i = 0
      while i + header <= p.count {
        guard p[i] == 0xFF, p[i + 1] & 0xF0 == 0xF0 else { break }
        let len = (Int(p[i + 3] & 3) << 11) | (Int(p[i + 4]) << 3) | (Int(p[i + 5]) >> 5)
        let headerLen = p[i + 1] & 1 == 0 ? header + 2 : header  // CRC present
        guard len > headerLen, (Int(p[i + 2]) >> 2) & 0xF < rates.count, i + len <= p.count else { break }
        i += len
        count += 1
      }
      return i
    }
    if count > 0 { try data.prefix(end).write(to: out) }
    return count
  }
}

/// Turns a session folder's crash-safe ADTS stream into the final audio.m4a (no re-encode).
enum Finalizer {
  static let partName = "audio.aac.part"
  static let audioName = "audio.m4a"
  static let marksName = "marks.jsonl"
  static let peaksName = "peaks.bin"

  /// Remuxes, checks the result opens, then deletes the part file. The part is kept if anything
  /// fails, so a bad finalize never loses audio. `pcmFrames` is the engine's exact 48 kHz count
  /// after a normal Stop; recovery reads the duration from the file instead.
  /// Returns nil when the folder holds no audio at all.
  static func finalize(_ folder: URL, recovered: Bool, pcmFrames: Int64? = nil, stopReason: String? = nil) async throws
    -> SavedRecording?
  {
    let fm = FileManager.default
    let part = folder.appendingPathComponent(partName)
    let audio = folder.appendingPathComponent(audioName)
    if fm.fileExists(atPath: part.path) {
      // AVFoundation picks the reader from the extension, and a crash may have cut the last frame.
      let aac = folder.appendingPathComponent("audio.tmp.aac")
      let tmp = folder.appendingPathComponent("audio.tmp.m4a")
      try? fm.removeItem(at: aac)
      try? fm.removeItem(at: tmp)
      if try Adts.copyWholeFrames(from: part, to: aac) == 0 {
        if !fm.fileExists(atPath: audio.path) {
          // Nothing was captured (stopped before the first frame): an empty folder is not a recording.
          let size = ((try? fm.attributesOfItem(atPath: part.path))?[.size] as? NSNumber)?.intValue ?? 0
          if size == 0 { try? fm.removeItem(at: folder) }
          return nil
        }
      } else {
        defer { try? fm.removeItem(at: aac) }
        try await passthrough(AVURLAsset(url: aac), to: tmp)
        guard try await durationMs(tmp) > 0 else { throw EngineError("finalized file does not open") }
        try? fm.removeItem(at: audio)
        try fm.moveItem(at: tmp, to: audio)
        try fm.removeItem(at: part)
      }
    }
    guard fm.fileExists(atPath: audio.path), var meta = Meta.read(folder) else { return nil }
    if let pcmFrames {
      meta.durationMs = pcmFrames * 1000 / Int64(meta.sampleRate)
    } else {
      meta.durationMs = try await durationMs(audio)
    }
    if meta.status == "recording" { meta.status = recovered ? "recovered" : "saved" }
    meta.stopReason = stopReason ?? meta.stopReason
    try meta.write(folder)
    return saved(folder, meta)
  }

  static func saved(_ folder: URL, _ meta: Meta) -> SavedRecording {
    SavedRecording(
      id: meta.id, folder: folder.path, createdAtMs: meta.createdAt, durationMs: meta.durationMs,
      marks: userMarks(Journal.read(folder.appendingPathComponent(marksName))),
      recovered: meta.status == "recovered", stopReason: meta.stopReason)
  }

  static func userMarks(_ entries: [JournalEntry]) -> [MarkResult] {
    entries.filter { $0.kind == "user" }.enumerated().map {
      MarkResult(id: $1.id, positionMs: $1.positionMs, index: Int64($0 + 1))
    }
  }

  /// Every folder with a part file that is not the live session: finalize it as recovered.
  static func recoverAll(_ root: URL, liveId: String?) async -> [SavedRecording] {
    let fm = FileManager.default
    var found: [SavedRecording] = []
    for dir in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    where dir.lastPathComponent != liveId && fm.fileExists(atPath: dir.appendingPathComponent(partName).path) {
      if let r = try? await finalize(dir, recovered: true) { found.append(r) }
    }
    return found
  }

  /// Copies the audio track of `asset` (optionally only `range`) into an .m4a, no re-encode.
  static func passthrough(_ asset: AVAsset, to url: URL, range: CMTimeRange? = nil) async throws {
    guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
      throw EngineError("This audio can't be exported.")
    }
    ex.outputURL = url
    ex.outputFileType = .m4a
    if let range { ex.timeRange = range }
    await ex.export()
    if ex.status != .completed { throw ex.error ?? EngineError("Export failed.") }
  }

  static func durationMs(_ url: URL) async throws -> Int64 {
    let d = try await AVURLAsset(url: url).load(.duration)
    return d.isNumeric ? Int64(d.seconds * 1000) : 0
  }
}
