import Foundation

public enum ModelFamily: String, CaseIterable, Codable, Sendable {
    case openAI
    case anthropic
    case google
    case deepSeek
    case zhipu
    case qwen
    case kimi
    case minimax
    case mistral
    case xAI
    case meta
    case bytedance
    case yi
    case xiaomi
    case nvidia
    case generic

    public var iconResourceName: String {
        switch self {
        case .openAI: "openai"
        case .anthropic: "anthropic"
        case .google: "gemini"
        case .deepSeek: "deepseek"
        case .zhipu: "zhipu"
        case .qwen: "qwen"
        case .kimi: "kimi"
        case .minimax: "minimax"
        case .mistral: "mistral"
        case .xAI: "xai"
        case .meta: "meta"
        case .bytedance: "doubao"
        case .yi: "yi"
        case .xiaomi: "xiaomimimo"
        case .nvidia: "nvidia"
        case .generic: "model-generic"
        }
    }
}

public enum ModelFamilyResolver {
    public static func resolve(_ modelName: String) -> ModelFamily {
        let name = modelName.lowercased()
        let mappings: [(ModelFamily, [String])] = [
            (.anthropic, ["anthropic", "claude", "opus", "sonnet", "haiku"]),
            (.google, ["google", "gemini", "gemma"]),
            (.deepSeek, ["deepseek"]),
            (.zhipu, ["zhipu", "chatglm", "glm-", "glm_", "codegeex"]),
            (.qwen, ["qwen", "qwq"]),
            (.kimi, ["kimi", "moonshot"]),
            (.minimax, ["minimax", "abab"]),
            (.mistral, ["mistral", "mixtral", "codestral", "magistral"]),
            (.xAI, ["xai", "grok"]),
            (.meta, ["meta", "llama"]),
            (.bytedance, ["bytedance", "doubao"]),
            (.yi, ["yi-", "yi_", "/yi"]),
            (.xiaomi, ["xiaomi", "mimo"]),
            (.nvidia, ["nvidia", "nemotron"]),
            (.openAI, ["openai", "chatgpt", "codex", "gpt-", "gpt_", "o1", "o3", "o4"]),
        ]

        for (family, needles) in mappings where needles.contains(where: name.contains) {
            return family
        }
        return .generic
    }
}

public enum ToolIconResolver {
    public static func resourceName(for toolName: String) -> String {
        switch ModelFamilyResolver.resolve(toolName) {
        case .openAI: "openai"
        case .anthropic: "anthropic"
        case .google: "gemini"
        case .deepSeek: "deepseek"
        case .zhipu: "zhipu"
        case .qwen: "qwen"
        case .kimi: "kimi"
        case .minimax: "minimax"
        case .mistral: "mistral"
        case .xAI: "xai"
        case .meta: "meta"
        case .bytedance: "doubao"
        case .yi: "yi"
        case .xiaomi: "xiaomimimo"
        case .nvidia: "nvidia"
        case .generic: "model-generic"
        }
    }
}
