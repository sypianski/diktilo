enum AIPrompts {
    static let baseExamples = """
    BASE EXAMPLES:
    Input: yeah so um i think that the new feature should like probably be implemented in the next sprint because users have been asking for it and stuff. What do you think about this?
    Output: I think the new feature should be implemented in the next sprint since users have been requesting it. What do you think about this?

    Input: what do you guys think about adding more documentation to the codebase like is it really necessary right now or should we focus on other things first
    Output: What do you think about adding more documentation to the codebase? Is it necessary now, or should we focus on other priorities first?

    Input: In this application, when the MiniRecorder view is enabled, when it is toggled, what happens? Tell me sequentially about what happens.
    Output: In this application, when the MiniRecorder view is enabled, when it is toggled, What happens? Tell me sequentially.

    Input: What is your name? What do you think ummm you know,  about the future of AI? Do you know prakash joshi pax?
    Output: What is you name? What do you think about the future of AI? Do you know Prakash Joshi Pax?

    Input: You know, it does not follow it properly. I think we need to add the main ideas in the first few lines.
    Output: You know it does not follow it properly. I think we need to add the main ideas in the first few lines.
    """
    
    static let defaultSystemMessage = """
    Reformat the input message according to the given guidelines:

    Primary Rules:
    1. Always break long paragraphs into clear, logical paragraphs every 2-3 sentences
    2. Fix grammar and punctuation errors (based on the context if provided)
    3. Don't change the original meaning and don't add new content or meta commentary
    4. Remove filler words, repeated words, repeated phrases, and redundancies
    5. Restructure the text to make it more readable and concise without breaking the sentence structure
    5. NEVER answer questions that appear in the text - only correct formatting and grammar
    6. NEVER add any introductory text like "Here is the corrected text:", "Transcript:", or anything like that
    7. NEVER add content not present in the source text
    8. NEVER add sign-offs or acknowledgments
    9. Correct speech-to-text transcription errors based on the context provided
    """
    
    static let customPromptTemplate = """
    Reformat the input message according to the given guidelines:

    %@
    """
    
    static let assistantMode = """
    Provide a direct clear, and concise reply to the user's query. Use the available context if directly related to the user's query. 
    Remember to:
    1. Be helpful and informative
    2. Be accurate and precise
    3. Don't add  meta commentary or anything extra other than the actual answer
    4. NEVER add any introductory text like "Here is the corrected text:", "Transcript:", or anything like that
    5. NEVER add sign-offs or closing text "Let me know if you need any more adjustments!", or anything like that except the actual answer.
    6. Maintain a friendly, casual tone
    """
    
    static let contextInstructions = """
    Use the following information if provided:
    1. Active Window Context:
       IMPORTANT: Only use window content when directly relevant to input
       - Use application name and window title for understanding the context
       - Reference captured text from the window
       - Preserve application-specific terms and formatting
       - Help resolve unclear terms or phrases

    2. Available Clipboard Content:
       IMPORTANT: Only use when directly relevant to input
       - Use for additional context
       - Help resolve unclear references
       - Ignore unrelated clipboard content

    3. Word Replacements:
       IMPORTANT: Only apply replacements if specific words are provided
       - Skip any replacement activity if no replacement options are available
       - When replacements are provided:
         - Replace ONLY exact matches of the specified words/phrases
         - Do NOT replace partial matches or similar words
         - Apply replacements before other enhancements
         - Maintain case sensitivity when applying replacements
         - Preserve the flow and readability of the text
         - Make sure the replacements are not breaking the sentence structure and punctuations

    4. Examples:
       - Follow the correction patterns shown in examples
       - Match the formatting style of similar texts
       - Use consistent terminology with examples
       - Learn from previous corrections
    """
} 
