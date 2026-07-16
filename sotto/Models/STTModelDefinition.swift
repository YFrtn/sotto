import Foundation

/// Which inference engine serves a given model.
enum STTEngineKind: Hashable {
    /// Qwen3 ASR via MLX (in-process, safetensors from HuggingFace).
    case mlx
    /// GigaAM v3 via the bundled `gigastt` sidecar server (ONNX Runtime).
    case gigaSTT
}

/// Available STT model variants.
struct STTModelDefinition: Identifiable, Hashable {
    let id: String
    let displayName: String
    /// Unique model identifier used as the persisted `selectedModelID`.
    /// For MLX models this is a HuggingFace repo; for GigaSTT a synthetic ID.
    let repoID: String
    let engine: STTEngineKind
    /// GigaAM v3 is Russian-only; MLX Qwen3 models are bilingual.
    let supportsLanguageSelection: Bool

    static let allModels: [STTModelDefinition] = [
        STTModelDefinition(
            id: "qwen3-0.6b-8bit",
            displayName: "Qwen3 ASR 0.6B (8-bit)",
            repoID: "mlx-community/Qwen3-ASR-0.6B-8bit",
            engine: .mlx,
            supportsLanguageSelection: true
        ),
        STTModelDefinition(
            id: "qwen3-1.7b-8bit",
            displayName: "Qwen3 ASR 1.7B (8-bit)",
            repoID: "mlx-community/Qwen3-ASR-1.7B-8bit",
            engine: .mlx,
            supportsLanguageSelection: true
        ),
        STTModelDefinition(
            id: "qwen3-1.7b-4bit",
            displayName: "Qwen3 ASR 1.7B (4-bit)",
            repoID: "mlx-community/Qwen3-ASR-1.7B-4bit",
            engine: .mlx,
            supportsLanguageSelection: true
        ),
        STTModelDefinition(
            id: "gigaam-v3",
            displayName: "GigaAM v3 (только русский)",
            repoID: "gigastt/gigaam-v3",
            engine: .gigaSTT,
            supportsLanguageSelection: false
        ),
    ]

    static let `default` = allModels[0]

    static func find(repoID: String) -> STTModelDefinition? {
        allModels.first { $0.repoID == repoID }
    }
}
