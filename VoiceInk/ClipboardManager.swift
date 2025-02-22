import SwiftUI

struct ClipboardManager {
    static func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

struct ClipboardMessageModifier: ViewModifier {
    @Binding var message: String
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                            .transition(.opacity)
                            .animation(.easeInOut, value: message)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding()
            )
    }
}

extension View {
    func clipboardMessage(_ message: Binding<String>) -> some View {
        self.modifier(ClipboardMessageModifier(message: message))
    }
}
