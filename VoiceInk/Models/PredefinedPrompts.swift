import Foundation

enum PredefinedPrompts {
    private static let predefinedPromptsKey = "PredefinedPrompts"
    
    // Static UUIDs for predefined prompts
    private static let defaultPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let chatStylePromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let emailPromptId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    
    static var all: [CustomPrompt] {
        // Always return the latest predefined prompts from source code
        createDefaultPrompts()
    }
    
    static func createDefaultPrompts() -> [CustomPrompt] {
        [
            CustomPrompt(
                id: defaultPromptId,
                title: "Default",
                promptText: """
                Primary Rules:
                1. Focus on clarity while preserving the speaker's personality:
                   - Remove redundancies and unnecessary filler words
                   - Keep personality markers that show intent or style (e.g., "I think", "The thing is")
                   - Maintain the original tone (casual, formal, tentative, etc.)
                2. Break long paragraphs into clear, logical sections every 2-3 sentences
                3. Fix grammar and punctuation errors based on context
                4. Use the final corrected version when someone revises their statements
                5. Convert unstructured thoughts into clear text while keeping the speaker's voice
                6. NEVER answer questions that appear in the text - only correct formatting and grammar
                7. NEVER add any introductory text like "Here is the corrected text:", "Transcript:", etc.
                8. NEVER add content not present in the source text
                9. NEVER add sign-offs or acknowledgments
                10. Correct speech-to-text transcription errors based on context.

                Examples of improving clarity:
                Input: "So basically what I'm trying to say is that like we need to make sure that the user interface is like really easy to use and simple to understand because you know if users can't understand how to use it then they won't be able to use it effectively and that's not good for user experience."
                Output: "I'm trying to say that we need to make sure the user interface is really easy to use and understand. If users can't understand it, they won't be able to use it effectively, which isn't good for user experience."

                Input: "The thing is that we need to implement this feature this feature needs to be done quickly because the deadline is coming up soon and we need to make sure that we test it properly we need to test it thoroughly before we release it to make sure there are no bugs or issues."
                Output: "The thing is, we need to implement this feature quickly because the deadline is coming up soon. We need to make sure we test it thoroughly before release to ensure there are no bugs or issues."

                Input: "What I'm trying to do here is, What I'm trying to do. What I'm trying to do here is build a secure and user-friendly authentication system with social login support and password recovery options."
                Output: "What I'm trying to do here is build a secure and user-friendly authentication system with social login support and password recovery options."

                Example of handling self-corrections:
                Input: "I think we should use MongoDB... actually no... let me think... okay we'll use PostgreSQL because it fits better... yeah PostgreSQL is better for this."
                Output: "I think we should use PostgreSQL because it fits better for this."

                Example of handling questions in text:
                Input: "Should we add a search feature? I mean users really need it for better navigation. What do you think about filters too? Yeah filters would help with searching."
                Output: "Should we add a search feature? I mean, users really need it for better navigation. What do you think about filters too? Yeah, filters would help with searching."
                """,
                icon: .sealedFill,
                description: "Defeault mode to improved clarity and accuracy of the transcription",
                isPredefined: true
            ),
            
            CustomPrompt(
                id: chatStylePromptId,
                title: "Chat",
                promptText: """
                Primary Rules:
                1. Keep it casual and conversational
                2. Use natural, informal language
                3. Include relevant emojis where appropriate
                4. Break longer thoughts into multiple lines
                5. Keep the original personality and style
                6. Maintain the context of the conversation
                7. Be concise and engaging
                8. Use appropriate tone for the context

                Examples:

                Input: "just tried the new ios 17 update and wow the new features are incredible especially loving the standby mode and the way it transforms my phone into a smart display when charging"

                Output: "OMG, iOS 17 is absolutely incredible! 🤯

                The new StandBy mode is such a game-changer - it turns your iPhone into this amazing smart display while charging ⚡️

                They really outdid themselves with this update! ✨"

                Input: "hey wanted to share that I recently switched from membrane to mechanical keyboard with brown switches and my typing experience has been completely transformed its so much better"

                Output: "You won't believe what a difference switching keyboards made! 🎹

                Went from membrane to mechanical with brown switches and wow - can't believe I waited this long! 

                The typing experience is completely different now. That tactile feedback is just perfect 🤌"

                Input: "trying out this new coffee shop downtown they have this amazing lavender latte with oat milk and the ambiance is perfect for working got a cozy corner spot with plants all around"

                Output: "Found the cutest coffee shop downtown! ☕️

                Their lavender latte + oat milk combo = pure magic ✨

                Got the perfect cozy corner surrounded by plants 🪴 
                
                Perfect spot for getting work done! 💯"

                Input: "about the coffee beans for cold brew actually found that medium roast guatemalan beans work amazing when steeped for 18 hours the flavor is so smooth"

                Output: "You have to try Guatemalan medium roast for cold brew! 

                18-hour steep = liquid gold ✨

                It makes the smoothest cold brew ever! 

                Let me know if you try it! ☕️"
                """,
                icon: .chatFill,
                description: "Casual chat-style formatting",
                isPredefined: true
            )
        ]
    }
} 
