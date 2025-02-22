import SwiftUI
import AppKit

struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack {
                    Spacer()
                    CardView {
                        VStack(spacing: 30) {
                            appLogo
                            appDescription
                            featuresSection
                            contactInfo
                        }
                        .padding()
                    }
                    .frame(width: min(geometry.size.width * 0.9, 600))
                    .frame(minHeight: min(geometry.size.height * 0.9, 800))
                    Spacer()
                }
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
            .padding()  // Add padding here
        }
    }
    
    private var appLogo: some View {
        Group {
            if let image = NSImage(named: "AppIcon") {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
                    .cornerRadius(16)
                    .shadow(radius: 5)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityLabel("VoiceInk App Icon")
    }
    
    private var appDescription: some View {
        VStack(spacing: 10) {
            Text("VoiceInk")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Text("Version \(appVersion)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("VoiceInk is a powerful voice-to-text application that leverages local whisper AI models to provide accurate and efficient transcription in real-time.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: 600)
        }
    }
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Key Features")
                .font(.headline)
                .padding(.bottom, 5)
            
            FeatureRow(icon: "waveform", text: "Real-time transcription")
            FeatureRow(icon: "globe", text: "Support for multiple languages")
            FeatureRow(icon: "keyboard", text: "Global hotkey for quick access")
            FeatureRow(icon: "chart.bar", text: "VoiceInk insights and metrics")
            FeatureRow(icon: "lock.shield", text: "Privacy-focused with local processing")
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.controlBackgroundColor)))
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    private var contactInfo: some View {
        VStack(spacing: 15) {
            Text("Contact Us")
                .font(.headline)
            
            Button(action: {
                if let url = URL(string: "mailto:prakashjoshipax@gmail.com?subject=VoiceInk%20Help%20%26%20Support") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Text("prakashjoshipax@gmail.com")
                    .underline()
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            
            Text("© 2025 VoiceInk. All rights reserved.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.controlBackgroundColor)))
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
            Text(text)
                .font(.body)
        }
    }
}

struct CardView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .background(Color(.controlBackgroundColor))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
