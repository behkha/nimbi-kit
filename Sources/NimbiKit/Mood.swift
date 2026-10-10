/// How the cloud feels. Every app maps its own states onto these (DESIGN.md 3.3); the last two
/// come from the cursor playing with it.
public enum Mood: Equatable {
    /// Nothing to do.
    case asleep
    /// Ready, nothing asked.
    case relaxed
    /// Work is happening; the more of it, the livelier it gets.
    case busy
    /// Something needs you.
    case asking
    /// It has been waiting a while.
    case impatient
    /// It has waited far too long, or several things are piling up.
    case angry
    /// Short relief: answered, finished, or you came back after a long time away.
    case happy
    /// Results are piling up and nobody has looked in a long while.
    case lonely
    /// The Mac, or a job, is running hot.
    case overheated
    /// The cursor is resting on it.
    case giggly
    /// The cursor has been shaken around it.
    case dizzy

    /// Moods the cursor is allowed to play over; anything that needs you comes first.
    public var isPlayful: Bool {
        switch self {
        case .asleep, .relaxed, .busy, .happy, .lonely: return true
        default: return false
        }
    }
}
