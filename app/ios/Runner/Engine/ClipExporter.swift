import AVFoundation

/// Lossless clip: copies the AAC packets of a time range into a new .m4a (no re-encode).
enum ClipExporter {
  private static let keepSeconds: TimeInterval = 24 * 3600

  /// Copies [startMs, endMs) of `folder/audio.m4a` into `outDir/fileName`, accurate to one AAC
  /// packet (~21 ms). The source is only read. Clips older than 24 h in `outDir` are removed.
  static func export(folder: URL, startMs: Int64, endMs: Int64, fileName: String, outDir: URL) async throws -> URL {
    guard endMs > startMs else { throw EngineError("empty range") }
    let fm = FileManager.default
    try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
    let now = Date()
    for f in (try? fm.contentsOfDirectory(at: outDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
      if let d = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
        now.timeIntervalSince(d) > keepSeconds
      {
        try? fm.removeItem(at: f)
      }
    }

    var safe = String(fileName.map { "\\/:*?\"<>|\n\r".contains($0) ? "-" : $0 }.prefix(120))
    if safe.trimmingCharacters(in: .whitespaces).isEmpty { safe = "clip.m4a" }
    let out = outDir.appendingPathComponent(safe)
    let tmp = outDir.appendingPathComponent("tmp-\(UUID().uuidString).m4a")
    defer { try? fm.removeItem(at: tmp) }
    let range = CMTimeRange(
      start: CMTime(value: startMs, timescale: 1000), end: CMTime(value: endMs, timescale: 1000))
    try await Finalizer.passthrough(
      AVURLAsset(url: folder.appendingPathComponent(Finalizer.audioName)), to: tmp, range: range)
    try? fm.removeItem(at: out)
    try fm.moveItem(at: tmp, to: out)
    return out
  }
}

/// Debug builds only: facts about an audio file that tests check (duration, test-tone pitch).
enum AudioProbe {
  /// Pitch is measured from 0.1 s to 0.35 s, past the encoder's priming.
  static func probe(_ path: String) throws -> AudioProbeResult {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let rate = file.processingFormat.sampleRate
    let durationMs = Int64(Double(file.length) * 1000 / file.fileFormat.sampleRate)
    let need = AVAudioFrameCount(rate * 0.35)
    guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: need) else {
      throw EngineError("no buffer")
    }
    try file.read(into: buf, frameCount: need)
    let have = Int(buf.frameLength)
    let from = Int(rate / 10)
    var rises = 0
    if let ch = buf.floatChannelData?[0], have > from + 1 {
      for i in (from + 1)..<have where ch[i - 1] < 0 && ch[i] >= 0 { rises += 1 }
    }
    let seconds = Double(have - from - 1) / rate
    return AudioProbeResult(durationMs: durationMs, startHz: seconds > 0 ? Double(rises) / seconds : 0)
  }
}
