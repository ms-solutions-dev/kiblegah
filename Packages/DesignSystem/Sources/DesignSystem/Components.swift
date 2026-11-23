import SwiftUI

/// A surface on `surface` with standard corner rounding.
public struct Card<Inner: View>: View {
    @Environment(\.theme) private var theme
    private let content: Inner

    public init(@ViewBuilder content: () -> Inner) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.surface, in: .rect(cornerRadius: 22))
    }
}

/// Kind of a notice: Karahat/warning, error, success.
public enum HintKind: Sendable {
    case warning
    case error
    case success
}

/// A notice banner with an icon and text – the meaning never lives in the color alone.
public struct Hint<Inner: View>: View {
    @Environment(\.theme) private var theme
    let kind: HintKind
    let content: Inner

    public init(_ kind: HintKind, @ViewBuilder content: () -> Inner) {
        self.kind = kind
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).accessibilityHidden(true)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .typography(.secondary)
        .foregroundStyle(on)
        .padding(14)
        .background(background, in: .rect(cornerRadius: 16))
    }

    private var icon: String {
        switch kind {
        case .warning: "exclamationmark.circle"
        case .error: "exclamationmark.triangle"
        case .success: "checkmark.circle"
        }
    }

    private var on: Color {
        switch kind {
        case .warning: theme.colors.warningText
        case .error: theme.colors.errorText
        case .success: theme.colors.successText
        }
    }

    private var background: Color {
        switch kind {
        case .warning: theme.colors.warningBackground
        case .error: theme.colors.errorBackground
        case .success: theme.colors.successBackground
        }
    }
}

/// Empty state: a heading and one sentence on what to do.
public struct EmptyState: View {
    @Environment(\.theme) private var theme
    let title: LocalizedStringKey
    let explanation: LocalizedStringKey

    public init(title: LocalizedStringKey, explanation: LocalizedStringKey) {
        self.title = title
        self.explanation = explanation
    }

    public var body: some View {
        VStack(spacing: 6) {
            Text(app: title).typography(.title2).foregroundStyle(theme.colors.text)
            Text(app: explanation).typography(.secondary).foregroundStyle(theme.colors.text2)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// Primary button on `accent`, at least 44 pt tall.
public struct PrimaryButton: ButtonStyle {
    @Environment(\.theme) private var theme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typography(.emphasized)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(theme.colors.onAccent)
            .background(theme.colors.accent, in: .rect(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Secondary button with a border in `control` (3:1).
public struct SecondaryButton: ButtonStyle {
    @Environment(\.theme) private var theme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typography(.emphasized)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(theme.colors.text)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.colors.control, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Page background for every screen; lists and forms hide their system gray so that
/// all tabs share the same background.
public struct PageBackground: ViewModifier {
    @Environment(\.theme) private var theme

    public func body(content: Content) -> some View {
        content
            .foregroundStyle(theme.colors.text)
            .scrollContentBackground(.hidden)
            .background(theme.colors.background.ignoresSafeArea())
    }
}

extension View {
    public func pageBackground() -> some View { modifier(PageBackground()) }
}
