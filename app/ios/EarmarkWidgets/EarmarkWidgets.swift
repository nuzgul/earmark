import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct EarmarkWidgets: WidgetBundle {
  var body: some Widget {
    RecordingLiveActivity()
    if #available(iOS 18.0, *) {
      RecordOrMarkControl()
    }
  }
}

// Brand tokens (app/lib/app/design/tokens.dart, dark): marigold is for marks only, red for live capture only.
extension Color {
  fileprivate init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
  fileprivate static let ink = Color(hex: 0x14130F)
  fileprivate static let paper = Color(hex: 0xF3EEE2)
  fileprivate static let paper2 = Color(hex: 0xADA593)
  fileprivate static let raised = Color(hex: 0x29261F)
  fileprivate static let marigold = Color(hex: 0xFFC23D)
  fileprivate static let onMarigold = Color(hex: 0x1A1405)
  fileprivate static let rec = Color(hex: 0xFF6B5E)
}

struct RecordingLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RecordingAttributes.self) { context in
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Status(state: context.state)
          Spacer(minLength: 8)
          Clock(state: context.state)
            .font(.title2.monospacedDigit().weight(.semibold))
        }
        Controls(state: context.state)
      }
      .padding(16)
      .activityBackgroundTint(Color.ink)
      .activitySystemActionForegroundColor(Color.paper)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Status(state: context.state).padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Clock(state: context.state).font(.title3.monospacedDigit().weight(.semibold))
        }
        DynamicIslandExpandedRegion(.bottom) {
          Controls(state: context.state).padding(.top, 4)
        }
      } compactLeading: {
        LiveDot(state: context.state)
      } compactTrailing: {
        Clock(state: context.state).frame(maxWidth: 48).font(.caption.monospacedDigit())
      } minimal: {
        LiveDot(state: context.state)
      }
      .keylineTint(Color.marigold)
    }
  }
}

private struct LiveDot: View {
  let state: RecordingAttributes.ContentState
  var body: some View {
    Image(systemName: state.running ? "waveform" : "pause.fill")
      .foregroundStyle(state.running ? Color.rec : Color.paper2)
      .accessibilityLabel(state.label)
  }
}

private struct Status: View {
  let state: RecordingAttributes.ContentState
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Circle().fill(state.running ? Color.rec : Color.paper2).frame(width: 8, height: 8)
        Text(state.label).font(.subheadline.weight(.semibold)).foregroundStyle(Color.paper)
      }
      Text(state.marks == 1 ? "1 mark" : "\(state.marks) marks")
        .font(.caption).foregroundStyle(Color.paper2)
    }
  }
}

/// Elapsed recording time, drawn by the system: no updates needed while it runs.
private struct Clock: View {
  let state: RecordingAttributes.ContentState
  var body: some View {
    let start = state.at.addingTimeInterval(-Double(state.elapsedMs) / 1000)
    Text(
      timerInterval: start...start.addingTimeInterval(24 * 3600), pauseTime: state.running ? nil : state.at,
      countsDown: false, showsHours: false
    )
    .multilineTextAlignment(.trailing)
    .foregroundStyle(Color.paper)
  }
}

private struct Controls: View {
  let state: RecordingAttributes.ContentState
  var body: some View {
    HStack(spacing: 10) {
      Button(intent: MarkIntent()) {
        Label("Mark", systemImage: "bookmark.fill")
          .font(.headline)
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .tint(Color.marigold)
      .foregroundStyle(Color.onMarigold)
      .accessibilityLabel("Bookmark this moment")

      Button(intent: PauseResumeIntent()) {
        Image(systemName: state.running ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
      }
      .tint(Color.raised)
      .foregroundStyle(Color.paper)
      .accessibilityLabel(state.running ? "Pause recording" : "Resume recording")

      Button(intent: StopIntent()) {
        Image(systemName: "stop.fill").frame(width: 44, height: 44)
      }
      .tint(Color.raised)
      .foregroundStyle(Color.paper)
      .accessibilityLabel("Stop and save")
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.capsule)
  }
}

@available(iOS 18.0, *)
struct RecordOrMarkControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "app.earmark.recorder.record-or-mark") {
      ControlWidgetButton(action: RecordOrMarkIntent()) {
        Label("Earmark", systemImage: "bookmark.fill")
      }
    }
    .displayName("Record or mark")
    .description("Starts a recording, or marks the moment if one is running.")
  }
}
