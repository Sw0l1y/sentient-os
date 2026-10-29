//  OnboardingDoubleTapSamples.swift
//  The Double Tap lesson's two vignettes, in the manner of Apple Intelligence's Smart Reply
//  card: a GroupBox with the real Mail or Messages icon, the incoming message, and the reply
//  field where the draft lands. The caret publishes its anchor so the swirl lands on it.
//  Replies stay in their fields; nothing sends.
//  Doc: Documentation - Onboarding.md (this folder).

import AppKit
import SwiftUI

struct DoubleTapDemoCaretAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// Sample content stays together so replacing the story cannot disturb the choreography.
private enum DemoEmail {
    static let sender = "Alex Morgan"
    static let subject = "Quick update before the client call"
    static let message = "Hey, how's the website refresh looking? I have a call with the client this afternoon and want to make sure I'm up to speed."
    static let reply = """
    Hey Alex, we're in good shape. We've finished the new pages and fixed the mobile issues, so we're just waiting on the client's final photos. If those come through tomorrow, we'll be ready to launch on Friday.

    Best,
    John
    """
}

struct DoubleTapDemoEmailWindow: View {
    let replied: Bool
    let waiting: Bool
    let reduceMotion: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    AppIconImage(bundleID: "com.apple.mail", size: 32, fallback: .emailAndCalendar)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DemoEmail.sender)
                            .font(.headline)
                        Text(DemoEmail.subject)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Space.s)
                    Text("Just now")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(DemoEmail.message)
                    .font(.callout)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                DemoReplyField(placeholder: "Reply to Alex", draft: DemoEmail.reply,
                               replied: replied, waiting: waiting, reduceMotion: reduceMotion,
                               minHeight: 64, showsDraftBadge: true)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(replied ? "Your draft reply" : "Empty reply field")
            }
            .padding(Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sample email")
    }
}

private enum DemoMessage {
    static let recipient = "Maya"
    static let incoming = "Yo, want to grab dinner tonight?\nGot a place in mind?"
    static let reply = "Yo sup, let's hit my favorite restaurant in downtown SF. Their kimchi is so good. You down for 7?"
}

struct DoubleTapDemoMessageWindow: View {
    let replied: Bool
    let waiting: Bool
    let reduceMotion: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    AppIconImage(bundleID: "com.apple.MobileSMS", size: 32, fallback: .conversations)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DemoMessage.recipient)
                            .font(.headline)
                        Text("iMessage")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Space.s)
                    Text("Today 5:42 PM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Messages with Maya")

                HStack {
                    Text(DemoMessage.incoming)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous))
                        .accessibilityLabel("Maya: \(DemoMessage.incoming)")
                    Spacer(minLength: Space.xxxl)
                }

                Divider()

                DemoReplyField(placeholder: "iMessage", draft: DemoMessage.reply,
                               replied: replied, waiting: waiting, reduceMotion: reduceMotion,
                               minHeight: 36, showsDraftBadge: false)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(replied ? "Draft reply to Maya" : "Empty iMessage field")
            }
            .padding(Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sample iMessage conversation")
    }
}

/// A text field drawn in the system's style: the caret and placeholder while empty, the draft
/// once it lands. The draft always takes part in layout, so the card never grows on paste.
private struct DemoReplyField: View {
    let placeholder: String
    let draft: String
    let replied: Bool
    let waiting: Bool
    let reduceMotion: Bool
    let minHeight: CGFloat
    let showsDraftBadge: Bool
    @Environment(\.pixelLength) private var pixelLength

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack(alignment: .topLeading) {
            Text(draft)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, showsDraftBadge ? Space.xxxl : 0)
                .opacity(replied ? 1 : 0)
                .accessibilityHidden(!replied)

            HStack(alignment: .center, spacing: 2) {
                DemoReplyCaret(replied: replied, waiting: waiting, reduceMotion: reduceMotion)
                Text(placeholder)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .opacity(replied ? 0 : 1)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .padding(Space.s)
        .background(shape.fill(.background))
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: pixelLength))
        .overlay(alignment: .topTrailing) {
            if showsDraftBadge && replied {
                Text("Draft")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .padding(6)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .animation(Motion.gated(Motion.standard, reduceMotion: reduceMotion), value: replied)
    }
}

/// A 1.5 × 18 accent caret that blinks like a text cursor while the lesson waits. It stays in
/// layout after the draft lands so the swirl's anchor never jumps.
private struct DemoReplyCaret: View {
    let replied: Bool
    let waiting: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.53, paused: !waiting || reduceMotion)) { context in
            let blinkOn = !waiting || reduceMotion
                || Int(context.date.timeIntervalSinceReferenceDate / 0.53) % 2 == 0
            RoundedRectangle(cornerRadius: 0.75)
                .fill(Color.accentColor)
                .frame(width: 1.5, height: 18)
                .opacity(replied || !blinkOn ? 0 : 1)
        }
        .anchorPreference(key: DoubleTapDemoCaretAnchor.self, value: .bounds) { $0 }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Double Tap vignettes") {
    HStack(alignment: .top, spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(spacing: Space.xl) {
                DoubleTapDemoEmailWindow(replied: false, waiting: true, reduceMotion: false)
                DoubleTapDemoEmailWindow(replied: true, waiting: false, reduceMotion: false)
                DoubleTapDemoMessageWindow(replied: false, waiting: true, reduceMotion: false)
                DoubleTapDemoMessageWindow(replied: true, waiting: false, reduceMotion: false)
            }
            .frame(width: 512)
            .padding(Space.xl)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
}
#endif
