import Foundation

public enum PromptTemplate {
    private static let pattern = #"\{selection\}|\{[Tt]ext\}|\{argument\s+name\s*=\s*"Text"\}|\{language\}"#

    public static func containsTextPlaceholder(_ template: String) -> Bool {
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(template.startIndex..., in: template)
        return regex.matches(in: template, range: range).contains {
            (template as NSString).substring(with: $0.range) != "{language}"
        }
    }

    /// A single pass prevents placeholder-like text in the selection being expanded again.
    public static func render(_ template: String, text: String, language: String) -> String {
        let regex = try! NSRegularExpression(pattern: pattern)
        let result = NSMutableString(string: template)
        let range = NSRange(template.startIndex..., in: template)
        for match in regex.matches(in: template, range: range).reversed() {
            let token = (template as NSString).substring(with: match.range)
            result.replaceCharacters(in: match.range, with: token == "{language}" ? language : text)
        }
        return result as String
    }
}
