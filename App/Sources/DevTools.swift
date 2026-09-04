import Foundation

struct DevTool {
    let id: String
    let name: String
    let group: String

    var url: String { "forge://home/tools/\(id).html" }
}

enum DevTools {
    static let all: [DevTool] = [
        DevTool(id: "json",      name: "JSON Formatter",     group: "Data"),
        DevTool(id: "jsonts",    name: "JSON → TypeScript",  group: "Data"),
        DevTool(id: "sql",       name: "SQL Formatter",      group: "Data"),
        DevTool(id: "jwt",       name: "JWT Decoder",        group: "Encoding"),
        DevTool(id: "base64",    name: "Base64",             group: "Encoding"),
        DevTool(id: "url",       name: "URL Tools",          group: "Encoding"),
        DevTool(id: "hash",      name: "Hash",               group: "Encoding"),
        DevTool(id: "uuid",      name: "UUID Generator",     group: "Generate"),
        DevTool(id: "timestamp", name: "Timestamp",          group: "Generate"),
        DevTool(id: "regex",     name: "Regex Tester",       group: "Generate"),
        DevTool(id: "color",     name: "Color",              group: "CSS"),
        DevTool(id: "gradient",  name: "Gradient",           group: "CSS"),
        DevTool(id: "shadow",    name: "Box Shadow",         group: "CSS")
    ]
}
