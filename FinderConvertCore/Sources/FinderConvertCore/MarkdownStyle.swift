import Foundation

// Visual style applied when converting Markdown to PDF or HTML
public enum MarkdownStyle: String, Codable, CaseIterable, Sendable {
    case modern
    case serif
    case github
    case plain

    public var displayName: String {
        switch self {
        case .modern: "Modern"
        case .serif: "Serif"
        case .github: "GitHub"
        case .plain: "Plain"
        }
    }

    public var css: String {
        switch self {
        case .modern:
            """
            body { font-family: -apple-system, sans-serif; max-width: 700px; margin: 40px auto; padding: 0 20px; line-height: 1.6; color: #333; }
            code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
            pre code { display: block; padding: 16px; overflow-x: auto; }
            blockquote { border-left: 4px solid #ddd; margin: 0; padding-left: 16px; color: #666; }
            h1, h2, h3 { margin-top: 1.5em; }
            hr { border: none; border-top: 1px solid #ddd; margin: 2em 0; }
            """
        case .serif:
            """
            body { font-family: Georgia, 'Times New Roman', serif; max-width: 650px; margin: 40px auto; padding: 0 20px; line-height: 1.7; color: #222; }
            h1, h2, h3, h4, h5, h6 { font-weight: 600; margin-top: 1.6em; line-height: 1.3; }
            h1 { font-size: 1.9em; }
            code { font-family: Menlo, monospace; background: #f7f5f0; padding: 2px 6px; border-radius: 3px; font-size: 0.85em; }
            pre code { display: block; padding: 16px; overflow-x: auto; }
            blockquote { border-left: 3px solid #b8a98a; margin: 0; padding-left: 18px; color: #555; font-style: italic; }
            hr { border: none; border-top: 1px solid #d8d2c4; margin: 2em 0; }
            a { color: #7a5c2e; }
            """
        case .github:
            """
            body { font-family: -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif; max-width: 760px; margin: 40px auto; padding: 0 20px; line-height: 1.5; color: #1f2328; }
            h1, h2 { padding-bottom: 0.3em; border-bottom: 1px solid #d1d9e0; }
            h1, h2, h3, h4, h5, h6 { margin-top: 1.5em; margin-bottom: 16px; font-weight: 600; line-height: 1.25; }
            code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; background: #f0f1f2; padding: 0.2em 0.4em; border-radius: 6px; font-size: 85%; }
            pre code { display: block; background: #f6f8fa; padding: 16px; border-radius: 6px; overflow-x: auto; line-height: 1.45; }
            blockquote { border-left: 0.25em solid #d1d9e0; margin: 0; padding: 0 1em; color: #59636e; }
            hr { border: none; height: 0.25em; background: #d1d9e0; margin: 24px 0; }
            a { color: #0969da; }
            """
        case .plain:
            """
            body { font-family: Helvetica, Arial, sans-serif; margin: 20px; line-height: 1.4; color: #000; }
            h1, h2, h3, h4, h5, h6 { margin-top: 1.2em; margin-bottom: 0.4em; }
            code { font-family: Courier, monospace; }
            pre code { display: block; margin: 1em 0; overflow-x: auto; }
            blockquote { margin: 0 0 0 2em; }
            hr { border: none; border-top: 1px solid #000; margin: 1.5em 0; }
            a { color: #000; }
            """
        }
    }
}
