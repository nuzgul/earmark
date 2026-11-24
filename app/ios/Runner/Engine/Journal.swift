import Foundation

/// One line of marks.jsonl. kind "system" marks an interruption (call) and is not a user mark.
/// Same format as the Android engine, so the Dart library reads both.
struct JournalEntry {
  let id: String
  let posFrames: Int64
  let sampleRate: Int
  let createdAt: Int64
  let source: String
  var kind = "user"
  var note: String? = nil

  var positionMs: Int64 { posFrames * 1000 / Int64(sampleRate) }

  func json() -> Data {
    var o: [String: Any] = [
      "id": id, "pos_frames": posFrames, "sample_rate": sampleRate,
      "created_at": createdAt, "source": source, "kind": kind,
    ]
    if let note { o["note"] = note }
    return (try? JSONSerialization.data(withJSONObject: o)) ?? Data()
  }
}

/// Append-only mark journal. Every line is fsynced before the mark is confirmed.
final class Journal {
  private let handle: FileHandle

  init(_ url: URL) throws {
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
  }

  func append(_ e: JournalEntry) throws {
    try handle.write(contentsOf: e.json() + Data([0x0A]))
    try handle.synchronize()
  }

  func close() { try? handle.close() }

  /// Reads every whole line; a line cut off by a crash is skipped.
  static func read(_ url: URL) -> [JournalEntry] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return data.split(separator: 0x0A).compactMap { line -> JournalEntry? in
      guard let o = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
        let id = o["id"] as? String,
        let pos = (o["pos_frames"] as? NSNumber)?.int64Value,
        let rate = (o["sample_rate"] as? NSNumber)?.intValue, rate > 0,
        let created = (o["created_at"] as? NSNumber)?.int64Value,
        let source = o["source"] as? String
      else { return nil }
      return JournalEntry(
        id: id, posFrames: pos, sampleRate: rate, createdAt: created, source: source,
        kind: o["kind"] as? String ?? "user", note: o["note"] as? String)
    }
  }
}

/// meta.json: what the Dart library reads. Written atomically.
struct Meta {
  let id: String
  let createdAt: Int64
  let sampleRate: Int
  let channels: Int
  let bitrate: Int
  var status: String  // recording | saved | recovered
  var durationMs: Int64 = 0
  var stopReason: String? = nil

  func write(_ folder: URL) throws {
    let o: [String: Any] = [
      "id": id, "created_at": createdAt, "sample_rate": sampleRate, "channels": channels,
      "bitrate": bitrate, "status": status, "duration_ms": durationMs,
      "stop_reason": stopReason.map { $0 as Any } ?? NSNull(),
    ]
    try JSONSerialization.data(withJSONObject: o)
      .write(to: folder.appendingPathComponent("meta.json"), options: .atomic)
  }

  static func read(_ folder: URL) -> Meta? {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent("meta.json")),
      let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let id = o["id"] as? String,
      let created = (o["created_at"] as? NSNumber)?.int64Value,
      let rate = (o["sample_rate"] as? NSNumber)?.intValue,
      let channels = (o["channels"] as? NSNumber)?.intValue,
      let bitrate = (o["bitrate"] as? NSNumber)?.intValue,
      let status = o["status"] as? String
    else { return nil }
    return Meta(
      id: id, createdAt: created, sampleRate: rate, channels: channels, bitrate: bitrate,
      status: status, durationMs: (o["duration_ms"] as? NSNumber)?.int64Value ?? 0,
      stopReason: o["stop_reason"] as? String)
  }
}

struct EngineError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
