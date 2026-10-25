import Foundation

nonisolated enum JudgePrompt {
    /// Part of the verdict cache key; bump when the rubric or schema changes.
    static let version = 1

    static let system = """
    You are a photo editor choosing which travel and event photos one person should post on social media.
    You will see photos from one person's day, labelled Image 1, Image 2, and so on. Judge each image on its own; do not compare images.
    Rate six things with exactly one of: bad, poor, fair, good, excellent.
    - sharpness: is the main subject in focus
    - exposure: not too dark, highlights not blown out, faces visible
    - composition: framing, straight horizon, clutter, where the subject sits in the frame
    - subject: how appealing the main subject is (a person's expression and pose, or how interesting the place or thing is)
    - moment: whether it captures something worth remembering (a laugh, dramatic light, action, a real moment rather than a stiff pose)
    - post_worthiness: whether a picky friend would post this exact photo
    Category, exactly one: me (one or two people fill the frame), me_with_view (one or two people shown small against a place), group (three or more people), view (a place or landscape with no person as the subject), food (food or drink is the subject), detail (a close-up of an object, texture, sign or small thing), other.
    Flags: list only what you actually see.
    Reason: one specific sentence under 12 words, in plain words a friend would use.
    Never identify, name or guess who anyone is.
    """

    static func scoreInstruction(count: Int) -> String {
        "Judge each of the \(count) images above on its own. Return one entry per image."
    }

    static let titleInstruction = """
    These photos will be posted together, in this order, as one story. Give the story a short, warm title of 3 to 6 words, \
    like the title of a journal entry. Plain words, no names, no hashtags, no emojis, no quotation marks.
    """

    static let bestOfInstruction = "These are near-identical shots of the same moment. Pick the one to post."
}
