import AVFoundation
import ActivityKit
import Flutter
import UIKit

/// Bridges the Flutter UI to RecorderEngine and owns the microphone permission request.
final class EngineHost: RecorderHostApi {
  private static var installed: EngineHost?
  private let engine = RecorderEngine.shared

  static func install(messenger: FlutterBinaryMessenger) {
    let host = EngineHost(events: RecorderEvents(binaryMessenger: messenger))
    RecorderHostApiSetup.setUp(binaryMessenger: messenger, api: host)
    installed = host
  }

  private init(events: RecorderEvents) {
    // The Dart side may not be listening yet (startup) or may be gone; the next heartbeat repeats the state.
    engine.onSnapshot = { s in Task { @MainActor in try? await events.onSnapshot(snapshot: s) } }
    engine.onMark = { m in Task { @MainActor in try? await events.onMark(mark: m) } }
    engine.onSaved = { r in Task { @MainActor in try? await events.onSaved(recording: r) } }
  }

  func snapshot() throws -> EngineSnapshot { engine.snapshot() }

  func start() async throws -> EngineSnapshot {
    let engine = self.engine
    let tone = await MainActor.run { engine.testTone }
    if !tone {
      switch AVAudioApplication.shared.recordPermission {
      case .granted: break
      case .undetermined:
        if await AVAudioApplication.requestRecordPermission() { break }
        fallthrough
      default:
        // iOS asks only once; after that the switch is in Settings.
        throw PigeonError(code: "mic_denied", message: "Earmark needs the microphone to record.", details: "permanent")
      }
    }
    _ = try await MainActor.run { try engine.start() }
    // "Recording" only once the microphone actually delivers audio.
    let deadline = Date().addingTimeInterval(3)
    while engine.snapshot().state == .starting, Date() < deadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    if engine.snapshot().state == .starting {
      _ = await engine.stop()
      throw PigeonError(
        code: "mic_busy", message: "The microphone didn't start. Close other apps that use it and try again.",
        details: nil)
    }
    return engine.snapshot()
  }

  func pause() throws -> EngineSnapshot { engine.pause() }
  func resume() throws -> EngineSnapshot { engine.resume() }
  func mark() throws -> MarkResult { try engine.mark(source: "app") }
  func stop() async throws -> SavedRecording? { await engine.stop() }
  func recover() async throws -> [SavedRecording] { await engine.recover() }

  func openAppSettings() throws {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
  }

  /// iOS shows Mark / Pause / Stop on the lock screen through a Live Activity.
  func notificationsAllowed() throws -> Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

  func recordingsRoot() throws -> String { engine.root.path }

  func exportClip(folder: String, startMs: Int64, endMs: Int64, fileName: String) async throws -> String {
    let clips = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("clips", isDirectory: true)
    do {
      return try await ClipExporter.export(
        folder: URL(fileURLWithPath: folder), startMs: startMs, endMs: endMs, fileName: fileName, outDir: clips
      ).path
    } catch {
      throw PigeonError(code: "clip_failed", message: "The clip could not be made.", details: error.localizedDescription)
    }
  }

  func probeAudio(path: String) async throws -> AudioProbeResult {
    #if DEBUG
      return try AudioProbe.probe(path)
    #else
      throw PigeonError(code: "debug_only", message: "Not available in this build.", details: nil)
    #endif
  }

  func useTestTone(on: Bool) throws {
    #if DEBUG
      engine.testTone = on
      // Test mode also keeps the screen on: a sleeping screen draws no frames and stalls the test.
      UIApplication.shared.isIdleTimerDisabled = on
    #endif
  }
}
