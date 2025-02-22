# Building VoiceInk

This guide provides detailed instructions for building VoiceInk from source.

## Prerequisites

Before you begin, ensure you have:
- macOS 14.0 or later
- Xcode (latest version recommended)
- Swift (latest version recommended)
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) properly set up
  - Follow the installation instructions in the whisper.cpp repository
  - Make sure you can build and run the basic examples
  - The library should be properly linked in your environment

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
   - The project uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for transcription
   - Clone and build whisper.cpp following their installation guide
   - Ensure the library is properly linked in your Xcode project
   - Test the whisper.cpp installation independently before proceeding

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
5. Make sure whisper.cpp is properly built and linked

For more help, please check the [issues](https://github.com/Beingpax/VoiceInk/issues) section or create a new issue. 