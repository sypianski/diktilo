# Building VoiceInk

This guide provides detailed instructions for building VoiceInk from source.

## Prerequisites

Before you begin, ensure you have:
- macOS 14.0 or later
- Xcode (latest version recommended)
- Swift (latest version recommended)
- whisper.cpp properly set up

## Building Steps

1. Clone the repository
```bash
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk
```

2. Open the project in Xcode
```bash
open VoiceInk.xcodeproj
```

3. Build and Run
- Build the project using Cmd+B or Product > Build
- Run the project using Cmd+R or Product > Run

## Development Setup

1. **Xcode Configuration**
   - Ensure you have the latest Xcode version
   - Install any required Xcode Command Line Tools

2. **Dependencies**
   - The project uses whisper.cpp for transcription
   - Make sure whisper.cpp is properly set up in your environment

3. **Building for Development**
   - Use the Debug configuration for development
   - Enable relevant debugging options in Xcode

4. **Testing**
   - Run the test suite before making changes
   - Ensure all tests pass after your modifications

## Troubleshooting

If you encounter any build issues:
1. Clean the build folder (Cmd+Shift+K)
2. Clean the build cache (Cmd+Shift+K twice)
3. Check Xcode and macOS versions
4. Verify all dependencies are properly installed

For more help, please check the [issues](https://github.com/Beingpax/VoiceInk/issues) section or create a new issue. 