import Foundation

public enum FrameworkDetector {
    private static let argumentRules: [([String], Framework)] = [
        (["next"], .next), (["vite"], .vite), (["astro"], .astro), (["remix"], .remix),
        (["nuxt"], .nuxt), (["svelte-kit"], .svelteKit), (["ng", "serve"], .angular),
        (["webpack"], .webpack), (["manage.py", "runserver"], .django), (["flask"], .flask),
        (["uvicorn"], .fastAPI), (["rails"], .rails), (["puma"], .rails),
        (["phx.server"], .phoenix), (["next-server"], .next),
    ]

    private static let jsRuntimes: Set<String> = ["node", "bun", "deno"]

    /// Only JS runtimes may borrow a framework from a package.json: a Python or Ruby
    /// server sitting in (or below) a JS project folder is not that project's framework.
    public static func isJSRuntime(_ p: ProcessRecord) -> Bool {
        if jsRuntimes.contains(p.name.lowercased()) { return true }
        guard let first = p.arguments.first?.split(whereSeparator: \.isWhitespace).first else {
            return false
        }
        return jsRuntimes.contains((String(first) as NSString).lastPathComponent.lowercased())
    }

    private static let dependencyRules: [(String, Framework)] = [
        ("next", .next), ("vite", .vite), ("astro", .astro), ("@remix-run/dev", .remix),
        ("nuxt", .nuxt), ("@sveltejs/kit", .svelteKit),
    ]

    public static func detect(arguments: [String], packageJSON: Data?) -> Framework? {
        let raw = tokenize(arguments)
        let stripped = raw.map(stripExtension)
        for (pattern, framework) in argumentRules
        where containsSequence(raw, pattern) || containsSequence(stripped, pattern) {
            return framework
        }
        if let deps = dependencyKeys(packageJSON) {
            for (key, framework) in dependencyRules where deps.contains(key) {
                return framework
            }
        }
        if let first = arguments.first {
            switch (first as NSString).lastPathComponent.lowercased() {
            case "bun": return .bun
            case "deno": return .deno
            default: break
            }
        }
        return nil
    }

    /// Splits each argument on whitespace (node's process.title rewrites argv into one
    /// string) and keeps only the last path component of each word, lowercased, so a
    /// directory named `next/` or `flask/` never tags a framework.
    private static func tokenize(_ arguments: [String]) -> [String] {
        arguments.flatMap { arg in
            arg.lowercased().split(whereSeparator: \.isWhitespace).compactMap { word in
                word.split(separator: "/").last.map(String.init)
            }
        }
    }

    /// `vite.js` -> `vite`, so script basenames match exactly.
    private static func stripExtension(_ token: String) -> String {
        guard let dot = token.lastIndex(of: "."), dot != token.startIndex else { return token }
        return String(token[..<dot])
    }

    private static func containsSequence(_ tokens: [String], _ pattern: [String]) -> Bool {
        guard !pattern.isEmpty, tokens.count >= pattern.count else { return false }
        for start in 0...(tokens.count - pattern.count)
        where Array(tokens[start..<start + pattern.count]) == pattern {
            return true
        }
        return false
    }

    private static func dependencyKeys(_ data: Data?) -> Set<String>? {
        guard let data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        var keys = Set<String>()
        for section in ["dependencies", "devDependencies"] {
            if let dict = obj[section] as? [String: Any] { keys.formUnion(dict.keys) }
        }
        return keys
    }
}
