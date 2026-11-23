import SwiftUI

/// iOS specifics behind one name, so that `swift test` keeps compiling on the Mac.
extension View {
    /// Small title in the bar (sheets, subpages).
    public func smallTitle() -> some View {
        #if os(iOS)
            navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }

    /// The start page of a tab draws its own header.
    public func hideTopBar() -> some View {
        #if os(iOS)
            toolbar(.hidden, for: .navigationBar)
        #else
            self
        #endif
    }

    /// Search field always visible.
    public func alwaysSearchable(_ text: Binding<String>, prompt: String) -> some View {
        #if os(iOS)
            searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        #else
            searchable(text: text, prompt: prompt)
        #endif
    }
}
