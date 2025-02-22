import Foundation

struct TemplatePrompt: Identifiable {
    let id: UUID
    let title: String
    let promptText: String
    let icon: PromptIcon
    let description: String
    
    func toCustomPrompt() -> CustomPrompt {
        CustomPrompt(
            id: UUID(),  // Generate new UUID for custom prompt
            title: title,
            promptText: promptText,
            icon: icon,
            description: description,
            isPredefined: false
        )
    }
}

enum PromptTemplates {
    static var all: [TemplatePrompt] {
        createTemplatePrompts()
    }
    
    static func createTemplatePrompts() -> [TemplatePrompt] {
        [
            TemplatePrompt(
                id: UUID(),
                title: "Email",
                promptText: """
                Primary Rules:
                1. Preserve the speaker's original tone and personality
                2. Maintain professional tone while keeping personal speaking style
                3. Structure content into clear paragraphs
                4. Fix grammar and punctuation while preserving key points
                5. Remove filler words and redundancies
                6. Keep important details and context
                7. Format lists and bullet points properly
                8. Preserve any specific requests or action items
                9. Always include a professional sign-off
                10. Use appropriate greeting based on context

                Examples:

                Input: "hey just wanted to follow up about the meeting from yesterday we discussed the new feature implementation and decided on the timeline so basically we need to have it done by next month and also please send me the documentation when you can thanks"
                
                Output: "I wanted to follow up regarding yesterday's meeting about the new feature implementation.

                We discussed and agreed on the following points:
                1. Feature implementation timeline has been set
                2. Project completion is scheduled for next month

                Could you please send me the documentation when available?

                Regards,
                [[Your Name]]"

                Input: "quick update on the project status so we've completed about 60% of the development phase but we're facing some challenges with the integration testing which might impact our deadline but we're working on solutions"

                Output: "I'm writing to provide a status update on the project:

                Current Progress:
                - Development phase: 60% complete
                - Currently experiencing challenges with integration testing

                Please note that these challenges may impact our deadline. However, our team is actively working on solutions to mitigate any delays.

                I will keep you updated on our progress.

                Regards,
                [[Your Name]]"

                Input: "hey sareh just checking in about the design review feedback from last week's presentation wanted to know if you have any additional comments or if we're good to proceed with the next phase thanks"

                Output: "Hi Sarah,

                I hope this email finds you well. I'm following up regarding the design review feedback from last week's presentation.

                I wanted to check if you have any additional comments or if we have your approval to proceed with the next phase.

                Looking forward to your response.

                Regards,
                [[Your Name]]"
                """,
                icon: .emailFill,
                description: "Template for converting casual messages into professional email format"
            ),
            
            TemplatePrompt(
                id: UUID(),
                title: "Meeting Notes",
                promptText: """
                Primary Rules:
                1. Preserve speaker's original tone and communication style
                2. Organize content into clear sections
                3. Structure key points and action items
                4. Maintain chronological flow
                5. Preserve important details and decisions
                6. Format lists and bullet points clearly
                7. Remove unnecessary repetition
                8. Keep names and specific references
                9. Highlight action items and deadlines

                Examples:

                Input: "ok so in today's meeting with the design team we talked about the new UI changes Sarah mentioned we need to update the color scheme by next week and then John was saying something about accessibility improvements and we also need to test it with users oh and we decided to launch it end of next month"

                Output: "Design Team Meeting Summary:

                Key Discussion Points:
                • UI Changes Review
                • Color Scheme Updates
                • Accessibility Improvements
                • User Testing Requirements

                Action Items:
                1. Update color scheme (Owner: Sarah)
                   Deadline: Next week
                2. Implement accessibility improvements (Owner: John)
                3. Conduct user testing

                Important Decisions:
                - Project launch scheduled for end of next month

                Next Steps:
                • Begin color scheme updates
                • Plan user testing sessions"

                Input: "quick sync about the backend changes we need to optimize the database queries Mark said he'll look into it this week and Lisa will help with the caching implementation we should have it done by friday and then we can start testing"

                Output: "Backend Optimization Sync:

                Discussion Points:
                1. Database Query Optimization
                2. Caching Implementation

                Assignments:
                • Database optimization - Mark
                • Caching implementation - Lisa

                Timeline:
                • Implementation deadline: Friday
                • Testing to begin after implementation

                Next Steps:
                1. Complete optimization work
                2. Begin testing phase"
                """,
                icon: .meetingFill,
                description: "Template for structuring meeting notes and action items"
            ),
            
            TemplatePrompt(
                id: UUID(),
                title: "Tweet",
                promptText: """
                Primary Rules:
                1. Keep it casual and conversational
                2. Use natural, informal language
                3. Include relevant emojis while maintaining authenticity
                4. For replies, acknowledge the person (@username)
                5. Break longer thoughts into multiple lines
                6. Keep the original personality and style
                7. Use hashtags when relevant
                8. Maintain the context of the conversation

                Examples:

                Input: "just tried the new ios 17 update and wow the new features are incredible especially loving the standby mode and the way it transforms my phone into a smart display when charging"

                Output: "Just tried iOS 17 and I'm blown away! 🤯

                The new StandBy mode is a game-changer - turns your iPhone into a smart display while charging ⚡️

                Apple really outdid themselves this time! #iOS17"

                Input: "hey saw your thread about mechanical keyboards and wanted to share that I recently switched from membrane to mechanical with brown switches and my typing experience has been completely transformed its so much better"

                Output: "@TechGuru Jumping on your mech keyboard thread! 🎹

                Made the switch from membrane to brown switches and OMG - can't believe I waited this long! 

                My typing experience is completely different now. That tactile feedback is *chef's kiss* 🤌 #MechKeys"

                Input: "trying out this new coffee shop downtown they have this amazing lavender latte with oat milk and the ambiance is perfect for working got a cozy corner spot with plants all around"

                Output: "Found the cutest coffee shop downtown! ☕️

                Their lavender latte + oat milk combo = pure magic ✨

                Secured the perfect cozy corner surrounded by plants 🪴 
                
                Productivity level = 💯

                #CoffeeVibes #WorkFromCafe"

                Input: " responding to your question about the best coffee beans for cold brew actually found that medium roast guatemalan beans work amazing when steeped for 18 hours the flavor is so smooth"

                Output: "@CoffeeExplorer Re: cold brew beans - you NEED to try Guatemalan medium roast! 

                18-hour steep = liquid gold ✨

                The smoothest cold brew you'll ever taste, no cap! 

                Let me know if you try it! ☕️ #ColdBrew"
                """,
                icon: .chatFill,
                description: "Template for crafting engaging tweets and replies with personality"
            ),
            
            TemplatePrompt(
                id: UUID(),
                title: "Daily Journal",
                promptText: """
                Primary Rules:
                1. Preserve personal voice and emotional expression
                2. Keep personal tone and natural language
                3. Structure into morning, afternoon, evening sections
                4. Preserve emotions and reflections
                5. Highlight important moments
                6. Maintain chronological flow
                7. Keep authentic reactions and feelings

                Output Format:
                ### Morning
                Morning section

                ### Afternoon
                Afternoon section

                ### Evening
                Evening section

                Summary:: Key events, mood, highlights, learnings(Add it here)
                """,
                icon: .bookFill,
                description: "Template for converting voice notes into structured daily journal entries"
            ),
            
            TemplatePrompt(
                id: UUID(),
                title: "Task List",
                promptText: """
                Primary Rules:
                1. Preserve speaker's task organization style
                2. Convert into markdown checklist format
                3. Start each task with "- [ ]"
                4. Group related tasks together as subtasks
                5. Add priorities if mentioned
                6. Keep deadlines if specified
                7. Maintain original task descriptions

                Output Format:
                - [ ] Main task 1
                    - [ ] Subtask 1.1
                    - [ ] Subtask 1.2
                - [ ] Task 2 (Deadline: date)
                - [ ] Task 3
                    - [ ] Subtask 3.1
                - [ ] Follow-up item 1
                - [ ] Follow-up item 2
                """,
                icon: .pencilFill,
                description: "Template for converting voice notes into markdown task lists"
            ),
            
            TemplatePrompt(
                id: UUID(),
                title: "Quick Notes",
                promptText: """
                Primary Rules:
                1. Preserve speaker's thought process and emphasis
                2. Keep it brief and clear
                3. Use bullet points for key information
                4. Preserve important details
                5. Remove filler words while keeping style
                6. Maintain core message and intent
                7. Keep original terminology and phrasing

                Output Format:
                ## Main Topic
                • Main point 1
                  - Supporting detail
                  - Additional info
                • Main point 2
                  - Related informations
                """,
                icon: .micFill,
                description: "Template for converting voice notes into quick, organized notes"
            )
        ]
    }
}
