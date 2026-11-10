import Foundation

public enum FrameworkDetector {
    private static let argumentRules: [([String], Framework)] = [
        (["next"], .next), (["vite"], .vite), (["astro"], .astro), (["remix"], .remix),
        (["nuxt"], .nuxt), (["svelte-kit"], .svelteKit), (["ng", "serve"], .angular),
        (["webpack"], .webpack), (["manage.py", "runserver"], .django), (["flask"], .flask),
        (["uvicorn"], .fastAPI), (["rails"], .rails), (["puma"], .rails),
        (["phx.server"], .phoenix),
    ]

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

    /// Splits on whitespace and "/", lowercased.
    private static func tokenize(_ arguments: [String]) -> [String] {
        arguments.flatMap { arg in
            arg.lowercased().split(whereSeparator: { $0 == "/" || $0.isWhitespace }).map(String.init)
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
