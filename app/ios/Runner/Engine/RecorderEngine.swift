import AVFoundation
import UIKit

/// The recording session, process-wide. It lives outside the Flutter UI, so the Live Activity and
/// the Control Center control can mark with no UI running.
///
/// Timing: `frames` counts 48 kHz PCM frames handed to the encoder. iOS delivers the microphone in
/// ~100 ms buffers, so a mark stores the counter plus the time since the newest buffer began
/// (capped at one buffer). Paused time is excluded by construction: audio between Pause and Resume
/// is cut out, even inside a buffer that straddles either moment.
///
/// Threads: `q` owns `session` and every Session field; AVAudioEngine and the timer stay on main.
final class RecorderEngine {
  static let shared = RecorderEngine()

  static let rate = 48_000.0
  static let bitrate = 96_000
  private static let minStartBytes: Int64 = 100 << 20
  private static let stopBytes: Int64 = 50 << 20

  /// Set by the Flutter bridge; called on the main thread.
  var onSnapshot: ((EngineSnapshot) -> Void)?
  var onMark: ((MarkResult) -> Void)?
  var onSaved: ((SavedRecording) -> Void)?

  /// Debug builds only: record a clock-paced test tone instead of the microphone (integration tests).
  var testTone = false

  /// Application Support: kept in the user's device backup, not shown in the Files app.
  let root: URL = {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("recordings", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()

  private let q = DispatchQueue(label: "app.earmark.engine", qos: .userInitiated)
  private let pcm = AVAudioFormat(
    commonFormat: .pcmFormatFloat32, sampleRate: RecorderEngine.rate, channels: 1, interleaved: false)!
  private var session: Session?
  private var audio: AVAudioEngine?  // main thread
  private var tone: Thread?  // main thread
  private var timer: Timer?  // main thread

  private final class Session {
    let id: String
    let folder: URL
    let part: FileHandle
    let peaks: FileHandle
    let journal: Journal
    let encoder: AacEncoder
    let tone: Bool
    var state = SessionState.starting
    var interruption: String?
    var frames: Int64 = 0
    var pausedAt: Double?  // host time of Pause
    var pausedPosition: Int64?  // frames at that moment
    var resumedAt = 0.0  // host time of the last Resume
    var silenced = false  // an interruption (call, Siri, alarm) holds the microphone
    var stopRequested = false
    var stopReason: String?
    var stopTask: Task<SavedRecording?, Never>?
    var level = 0.0
    var markCount: Int64 = 0
    var lastHost = 0.0  // host time of the newest chunk's first frame
    var lastLen = 0  // its length; 0 = no live estimate yet
    var lastFrames: Int64 = -1
    var lastAdvance = 0.0
    var lastSync = 0.0
    var lastStorage = 0.0
    var lastRetry = 0.0
    var peak: Float = 0
    var peakFrames = 0
    var pendingPeaks = Data()
    var shown = ""  // what the Live Activity shows now

    init(id: String, folder: URL, encoder: AacEncoder, tone: Bool) throws {
      self.id = id
      self.folder = folder
      self.encoder = encoder
      self.tone = tone
      part = try Self.create(folder.appendingPathComponent(Finalizer.partName))
      peaks = try Self.create(folder.appendingPathComponent(Finalizer.peaksName))
      journal = try Journal(folder.appendingPathComponent(Finalizer.marksName))
    }

    private static func create(_ url: URL) throws -> FileHandle {
      FileManager.default.createFile(atPath: url.path, contents: nil)
      return try FileHandle(forWritingTo: url)
    }

    func close() {
      try? part.synchronize()
      try? part.close()
      try? peaks.close()
      journal.close()
    }
  }

  private init() {
    let nc = NotificationCenter.default
    nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
      self?.interrupted(n)
    }
    // Route change (Bluetooth mic lost, headset plugged) or the engine stopped by the system.
    nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] n in
      guard let self, let changed = n.object as? AVAudioEngine, changed === self.audio else { return }
      self.restartMic()
    }
    nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) {
      [weak self] _ in self?.restartMic()
    }
  }

  static func hostNow() -> Double { AVAudioTime.seconds(forHostTime: mach_absolute_time()) }

  var isActive: Bool { q.sync { session != nil } }

  func snapshot() -> EngineSnapshot { q.sync { makeSnapshot() } }

  // MARK: Commands

  /// Starts capture (main thread); the caller has the microphone permission.
  /// State stays `starting` until frames arrive.
  func start() throws -> EngineSnapshot {
    if isActive { return snapshot() }
    if freeBytes() < Self.minStartBytes {
      throw PigeonError(
        code: "low_storage", message: "Not enough free space to record. Free up at least 100 MB and try again.",
        details: nil)
    }
    guard let encoder = AacEncoder(pcm: pcm, bitrate: Self.bitrate) else {
      throw PigeonError(code: "encoder", message: "This iPhone's audio encoder could not start.", details: nil)
    }
    let id = UUID().uuidString.lowercased()
    let folder = root.appendingPathComponent(id, isDirectory: true)
    let s: Session
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try Meta(
        id: id, createdAt: nowMs(), sampleRate: Int(Self.rate), channels: 1, bitrate: Self.bitrate,
        status: "recording"
      ).write(folder)
      s = try Session(id: id, folder: folder, encoder: encoder, tone: testTone)
    } catch {
      try? FileManager.default.removeItem(at: folder)
      throw PigeonError(
        code: "storage", message: "Earmark couldn't create the recording file.", details: error.localizedDescription)
    }
    q.sync { session = s }
    do {
      if s.tone { startTone(s) } else { try startMic(s) }
    } catch {
      stopCapture(s)
      q.sync { session = nil }
      s.close()
      try? FileManager.default.removeItem(at: folder)
      throw PigeonError(
        code: "mic_busy", message: "The microphone isn't available right now. Close other apps that use it and try again.",
        details: error.localizedDescription)
    }
    startTimer()
    return q.sync {
      publish()
      return makeSnapshot()
    }
  }

  func pause() -> EngineSnapshot {
    q.sync {
      if let s = session, !s.stopRequested, s.state != .paused {
        s.pausedPosition = position(s)
        s.pausedAt = Self.hostNow()
        s.state = .paused
        s.interruption = nil
        publish()
      }
      return makeSnapshot()
    }
  }

  func resume() -> EngineSnapshot {
    q.sync {
      if let s = session, !s.stopRequested, s.state == .paused {
        s.pausedAt = nil
        s.pausedPosition = nil
        s.resumedAt = Self.hostNow()
        s.lastLen = 0
        if s.silenced { setState(s, .interrupted, "call") } else { setState(s, .recording, nil) }
      }
      return makeSnapshot()
    }
  }

  /// Records a mark at the current position and fsyncs it before returning. Any thread.
  func mark(source: String) throws -> MarkResult {
    let result: MarkResult = try q.sync {
      guard let s = session, !s.stopRequested else {
        throw PigeonError(code: "not_recording", message: "Nothing is recording.", details: nil)
      }
      let e = JournalEntry(
        id: UUID().uuidString.lowercased(), posFrames: position(s), sampleRate: Int(Self.rate), createdAt: nowMs(),
        source: source)
      try s.journal.append(e)
      s.markCount += 1
      publish()
      return MarkResult(id: e.id, positionMs: e.positionMs, index: s.markCount)
    }
    DispatchQueue.main.async { self.onMark?(result) }
    return result
  }

  /// Stops, finalizes and returns the saved recording. A second caller (app and Live Activity at
  /// once) gets the first one's result.
  func stop(reason: String? = nil) async -> SavedRecording? {
    let task: Task<SavedRecording?, Never>? = q.sync {
      guard let s = session else { return nil }
      if let t = s.stopTask { return t }
      s.stopRequested = true
      s.stopReason = reason
      s.state = .finalizing
      publish()
      let t = Task { await self.finish(s) }
      s.stopTask = t
      return t
    }
    return await task?.value
  }

  /// Finalizes sessions a crash left behind.
  func recover() async -> [SavedRecording] {
    let live = q.sync { session?.id }
    return await Finalizer.recoverAll(root, liveId: live)
  }

  private func finish(_ s: Session) async -> SavedRecording? {
    await MainActor.run { self.stopCapture(s) }
    // Runs after every buffer captured before Stop; later ones are dropped by consume().
    let frames: Int64 = q.sync {
      do {
        try s.part.write(contentsOf: s.encoder.encode(nil))
      } catch {
        NSLog("Earmark: flushing the encoder failed: \(error)")
      }
      flushPeaks(s)
      return s.frames
    }
    s.close()
    var saved: SavedRecording?
    do {
      saved = try await Finalizer.finalize(s.folder, recovered: false, pcmFrames: frames, stopReason: s.stopReason)
    } catch {
      // The part file stays on disk; recover() finishes it on the next launch.
      NSLog("Earmark: finalize failed: \(error)")
    }
    q.sync {
      session = nil
      publish()
    }
    await MainActor.run {
      self.timer?.invalidate()
      self.timer = nil
      LiveActivity.end()
      if let saved { self.onSaved?(saved) }
    }
    return saved
  }

  // MARK: Capture

  private func startMic(_ s: Session) throws {
    let av = AVAudioSession.sharedInstance()
    try av.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth])
    try? av.setPreferredSampleRate(Self.rate)
    try av.setActive(true)
    audio?.inputNode.removeTap(onBus: 0)
    audio?.stop()

    let pcm = self.pcm
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0, let conv = AVAudioConverter(from: format, to: pcm) else {
      throw EngineError("no microphone input")
    }
    conv.downmix = true
    input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, when in
      let host =
        when.isHostTimeValid
        ? AVAudioTime.seconds(forHostTime: when.hostTime)
        : Self.hostNow() - Double(buffer.frameLength) / format.sampleRate
      guard let chunk = Self.convert(buffer, with: conv, to: pcm) else { return }
      self.q.async { self.consume(s, chunk, host: host) }
    }
    engine.prepare()
    audio = engine
    try engine.start()
  }

  /// Test source: exactly as many frames as real time allows, so a test can check timing without a
  /// simulator's microphone. The pitch encodes the second of audio (300 Hz + 20 Hz × second).
  private func startTone(_ s: Session) {
    let pcm = self.pcm
    let t = Thread {
      let n = 1024
      let start = Self.hostNow()
      var produced: Int64 = 0
      var phase = 0.0
      while !Thread.current.isCancelled {
        let wait = start + Double(produced + Int64(n)) / Self.rate - Self.hostNow()
        if wait > 0 { Thread.sleep(forTimeInterval: wait + 0.001) }
        guard let buf = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: AVAudioFrameCount(n)) else { return }
        buf.frameLength = AVAudioFrameCount(n)
        let ch = buf.floatChannelData![0]
        for i in 0..<n {
          let hz = 300.0 + 20.0 * Double((produced + Int64(i)) / 48_000)
          phase += 2 * Double.pi * hz / Self.rate
          ch[i] = Float(sin(phase) * 8000 / 32768)
        }
        let host = start + Double(produced) / Self.rate
        produced += Int64(n)
        self.q.async { self.consume(s, buf, host: host) }
      }
    }
    t.qualityOfService = .userInteractive
    t.start()
    tone = t
  }

  private func stopCapture(_ s: Session) {
    tone?.cancel()
    tone = nil
    if let audio {
      audio.inputNode.removeTap(onBus: 0)
      audio.stop()
    }
    audio = nil
    if !s.tone { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
  }

  /// Rebuilds capture after an interruption, a route change or a media-services reset (main thread).
  private func restartMic() {
    guard let s = q.sync(execute: { session }), !s.tone, !q.sync(execute: { s.stopRequested }) else { return }
    do {
      try startMic(s)
      q.sync {
        s.lastLen = 0
        if s.silenced {
          s.silenced = false
          if s.state == .interrupted { setState(s, .recording, nil) }
        }
      }
    } catch {
      q.sync {
        if s.pausedAt == nil && s.state != .interrupted { setState(s, .interrupted, "mic_lost") }
      }
    }
  }

  private func interrupted(_ n: Notification) {
    guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: raw)
    else { return }
    if type == .ended {
      restartMic()
      return
    }
    q.sync {
      guard let s = session, !s.tone, !s.stopRequested, !s.silenced else { return }
      let at = position(s)
      s.silenced = true
      try? s.journal.append(
        JournalEntry(
          id: UUID().uuidString.lowercased(), posFrames: at, sampleRate: Int(Self.rate), createdAt: nowMs(),
          source: "system", kind: "system", note: "call"))
      if s.state == .recording || s.state == .starting { setState(s, .interrupted, "call") }
    }
  }

  /// One chunk of 48 kHz mono PCM whose first frame was captured at `host` (on q).
  private func consume(_ s: Session, _ buf: AVAudioPCMBuffer, host: Double) {
    if s.stopRequested || s.silenced { return }
    let n = Int(buf.frameLength)
    var from = 0
    var to = n
    if let p = s.pausedAt { to = min(max(Int((p - host) * Self.rate), 0), n) }
    if s.resumedAt > host { from = min(max(Int((s.resumedAt - host) * Self.rate), 0), n) }
    if from >= to { return }
    let chunk = from == 0 && to == n ? buf : slice(buf, from, to)
    let count = to - from
    do {
      try s.part.write(contentsOf: s.encoder.encode(chunk))
    } catch {
      NSLog("Earmark: writing audio failed: \(error)")
      Task { _ = await self.stop(reason: "error") }  // keep what was captured
      return
    }

    let ch = chunk.floatChannelData![0]
    var chunkPeak: Float = 0
    for i in 0..<count {
      let v = abs(ch[i])
      if v > chunkPeak { chunkPeak = v }
      if v > s.peak { s.peak = v }
      s.peakFrames += 1
      if s.peakFrames == 2400 {  // one peaks.bin byte per 50 ms
        s.pendingPeaks.append(UInt8(min(s.peak, 1) * 255))
        s.peak = 0
        s.peakFrames = 0
      }
    }
    s.frames += Int64(count)
    s.lastHost = host + Double(from) / Self.rate
    s.lastLen = count
    let db = chunkPeak > 0 ? 20 * log10(Double(chunkPeak)) : -90
    s.level = max(s.level, min(max((db + 60) / 60, 0), 1))
    if s.state == .starting || (s.state == .interrupted && s.interruption == "mic_lost") {
      setState(s, .recording, nil)
    }
    let now = Self.hostNow()
    if now - s.lastSync > 5 {
      try? s.part.synchronize()
      flushPeaks(s)  // a recovered recording keeps its waveform too
      s.lastSync = now
    }
  }

  private func flushPeaks(_ s: Session) {
    guard !s.pendingPeaks.isEmpty else { return }
    try? s.peaks.write(contentsOf: s.pendingPeaks)
    s.pendingPeaks.removeAll()
  }

  private func slice(_ b: AVAudioPCMBuffer, _ from: Int, _ to: Int) -> AVAudioPCMBuffer {
    let out = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: AVAudioFrameCount(to - from))!
    out.frameLength = AVAudioFrameCount(to - from)
    out.floatChannelData![0].update(from: b.floatChannelData![0] + from, count: to - from)
    return out
  }

  /// Hardware format (any rate, any channel count) → 48 kHz mono float, in a buffer we own.
  private static func convert(_ buffer: AVAudioPCMBuffer, with conv: AVAudioConverter, to format: AVAudioFormat)
    -> AVAudioPCMBuffer?
  {
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 64
    guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
    var fed = false
    var error: NSError?
    _ = conv.convert(to: out, error: &error) { _, status in
      if fed {
        status.pointee = .noDataNow
        return nil
      }
      fed = true
      status.pointee = .haveData
      return buffer
    }
    return out.frameLength > 0 ? out : nil
  }

  // MARK: State (on q)

  /// Frames recorded up to now: the counter plus the time since the newest chunk began, capped at
  /// one chunk. Paused: the position at the moment of Pause.
  private func position(_ s: Session) -> Int64 {
    if let p = s.pausedPosition { return p }
    guard s.state == .recording, !s.silenced, s.lastLen > 0 else { return s.frames }
    let extra = (Self.hostNow() - s.lastHost) * Self.rate - Double(s.lastLen)
    return s.frames + Int64(min(max(extra, 0), Double(s.lastLen)))
  }

  private func makeSnapshot(resetLevel: Bool = false) -> EngineSnapshot {
    guard let s = session else {
      return EngineSnapshot(state: .idle, positionMs: 0, level: 0, markCount: 0, freeBytes: freeBytes())
    }
    let level = s.level
    if resetLevel { s.level = 0 }
    return EngineSnapshot(
      state: s.state, recordingId: s.id, positionMs: position(s) * 1000 / Int64(Self.rate), level: level,
      markCount: s.markCount, interruption: s.interruption, freeBytes: freeBytes())
  }

  private func setState(_ s: Session, _ state: SessionState, _ why: String?) {
    if state == .recording { s.lastAdvance = Self.hostNow() }
    s.state = state
    s.interruption = why
    publish()
  }

  /// Sends the snapshot to the UI; the Live Activity only when what it shows changed.
  private func publish(resetLevel: Bool = false) {
    let snap = makeSnapshot(resetLevel: resetLevel)
    var activity: EngineSnapshot?
    if let s = session {
      let key = "\(s.state.rawValue)|\(s.interruption ?? "")|\(s.markCount)"
      if key != s.shown {
        s.shown = key
        activity = snap
      }
    }
    DispatchQueue.main.async {
      self.onSnapshot?(snap)
      if let activity { LiveActivity.show(activity) }
    }
  }

  private func freeBytes() -> Int64 {
    var url = root
    url.removeAllCachedResourceValues()
    return (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
      .volumeAvailableCapacityForImportantUsage ?? 0
  }

  // MARK: Heartbeat (main thread)

  private func startTimer() {
    timer?.invalidate()
    let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  /// Heartbeat; also the stall watchdog: "Recording" is never shown while frames stand still.
  private func tick() {
    let now = Self.hostNow()
    var retry = false
    var lowStorage = false
    q.sync {
      guard let s = session, !s.stopRequested else { return }
      if s.frames != s.lastFrames {
        s.lastFrames = s.frames
        s.lastAdvance = now
      } else if s.state == .recording && now - s.lastAdvance > 1 {
        s.state = .interrupted
        s.interruption = "mic_lost"
      }
      if !s.tone && s.state == .interrupted && now - s.lastRetry > 2 {
        s.lastRetry = now
        retry = true
      }
      if now - s.lastStorage > 15 {
        s.lastStorage = now
        lowStorage = freeBytes() < Self.stopBytes
      }
      publish(resetLevel: true)
    }
    if retry { restartMic() }
    if lowStorage { Task { _ = await self.stop(reason: "low_storage") } }
  }
}

/// PCM (48 kHz mono float) → AAC-LC packets, each with its ADTS header (crash-safe stream).
final class AacEncoder {
  private let converter: AVAudioConverter
  private let out: AVAudioCompressedBuffer

  init?(pcm: AVAudioFormat, bitrate: Int) {
    var d = AudioStreamBasicDescription(
      mSampleRate: pcm.sampleRate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0, mBytesPerPacket: 0,
      mFramesPerPacket: 1024, mBytesPerFrame: 0, mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0)
    guard let aac = AVAudioFormat(streamDescription: &d), let c = AVAudioConverter(from: pcm, to: aac) else {
      return nil
    }
    c.bitRate = bitrate
    converter = c
    out = AVAudioCompressedBuffer(
      format: aac, packetCapacity: 16, maximumPacketSize: max(c.maximumOutputPacketSize, 2048))
  }

  /// Encodes `buffer` (nil = end of stream, flushes the encoder) and returns whole ADTS frames.
  func encode(_ buffer: AVAudioPCMBuffer?) -> Data {
    var result = Data()
    var fed = false
    while true {
      var error: NSError?
      let status = converter.convert(to: out, error: &error) { _, st in
        if let buffer, !fed {
          fed = true
          st.pointee = .haveData
          return buffer
        }
        st.pointee = buffer == nil ? .endOfStream : .noDataNow
        return nil
      }
      if let descriptions = out.packetDescriptions {
        for i in 0..<Int(out.packetCount) {
          let p = descriptions[i]
          let size = Int(p.mDataByteSize)
          result.append(contentsOf: Adts.frameHeader(payload: size, sampleRate: 48_000, channels: 1))
          result.append(out.data.advanced(by: Int(p.mStartOffset)).assumingMemoryBound(to: UInt8.self), count: size)
        }
      }
      if status != .haveData { break }
    }
    return result
  }
}
