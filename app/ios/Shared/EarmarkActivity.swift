// Compiled into both the app and the widget extension. The intents' perform() runs in the app
// process (LiveActivityIntent / AudioRecordingIntent); the extension only draws the buttons.
import ActivityKit
import AppIntents
import Foundation

/// What the Live Activity shows. The timer is drawn by the system from `at - elapsedMs`, so it
/// runs without updates; the app updates the activity only on state changes and marks.
struct RecordingAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var running: Bool
    var label: String
    var elapsedMs: Int64
    var at: Date
    var marks: Int
  }
}

/// The app sets this at launch; it stays nil inside the widget extension.
enum EarmarkControls {
  static var perform: ((String) async throws -> Void)?
}

struct MarkIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Mark this moment"

  func perform() async throws -> some IntentResult {
    try await EarmarkControls.perform?("mark")
    return .result()
  }
}

struct PauseResumeIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Pause or resume recording"

  func perform() async throws -> some IntentResult {
    try await EarmarkControls.perform?("toggle")
    return .result()
  }
}

struct StopIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Stop and save recording"

  func perform() async throws -> some IntentResult {
    try await EarmarkControls.perform?("stop")
    return .result()
  }
}

/// Control Center, lock screen or Action Button: starts a recording (with its Live Activity), or
/// marks the one in progress.
@available(iOS 18.0, *)
struct RecordOrMarkIntent: AudioRecordingIntent {
  static let title: LocalizedStringResource = "Record or mark"

  func perform() async throws -> some IntentResult {
    try await EarmarkControls.perform?("record_or_mark")
    return .result()
  }
}
