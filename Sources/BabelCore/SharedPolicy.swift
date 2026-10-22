import BabelPolicy
import Foundation

public enum SharedPolicy {
    public static let version = Int(bp_version())
    public static func challenge(supported: Bool, reliable: Bool, learned: Bool, newSense: Bool = false, helps: Int, used: Int) -> Bool {
        bp_challenge(supported ? 1 : 0, reliable ? 1 : 0, learned ? 1 : 0, newSense ? 1 : 0, Int32(helps), Int32(used)) != 0
    }
    public static func anchor(level: Int, supported: Bool = false, focus: Bool = false,
                              newSense: Bool = false, cooldown: Bool = false, selected: Bool = false) -> Bool {
        bp_anchor(Int32(level), supported ? 1 : 0, focus ? 1 : 0, newSense ? 1 : 0, cooldown ? 1 : 0, selected ? 1 : 0) != 0
    }
    public static func contains(_ text: String, unit: String) -> Bool {
        bp_contains(text.precomposedStringWithCanonicalMapping.lowercased(), unit.precomposedStringWithCanonicalMapping.lowercased()) != 0
    }
    public static func sameStory(_ a: String, _ b: String) -> Bool {
        let a = a.precomposedStringWithCanonicalMapping.lowercased(), b = b.precomposedStringWithCanonicalMapping.lowercased()
        return bp_same_story(a, b) != 0 && bp_same_story(b, a) != 0
    }
    public static func feedURL(topic: Int) -> URL { URL(string: String(cString: bp_feed_url(Int32(topic))))! }
    public static var rewritePrompt: String { String(cString: bp_rewrite_prompt()) }
    public static func fetch(enabled: Bool, background: Bool, backgroundRequest: Bool, manual: Bool, attempt: Double, success: Double) -> Bool {
        bp_fetch(enabled ? 1 : 0, background ? 1 : 0, backgroundRequest ? 1 : 0, manual ? 1 : 0, attempt, success) != 0
    }
    public static func score(age: Double, interest: Double, matches: Double, readability: Double = 0.5, seen: Bool) -> Double {
        bp_news_score(age, interest, matches, readability, seen ? 1 : 0)
    }
    public static func digest(enabled: Bool, background: Bool, notify: Bool, permitted: Bool, reading: Bool, quiet: Bool, sent: Int, fresh: Int) -> Bool {
        bp_digest(enabled ? 1 : 0, background ? 1 : 0, notify ? 1 : 0, permitted ? 1 : 0, reading ? 1 : 0, quiet ? 1 : 0, Int32(sent), Int32(fresh)) != 0
    }
}
