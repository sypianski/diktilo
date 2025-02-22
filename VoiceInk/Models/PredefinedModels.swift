import Foundation

struct PredefinedModel: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let displayName: String
    let size: String
    let language: String
    let description: String
    let speed: Double
    let accuracy: Double
    let ramUsage: Double
    let hash: String
    
    var downloadURL: String {
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)"
    }
    
    var filename: String {
        "\(name).bin"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: PredefinedModel, rhs: PredefinedModel) -> Bool {
        lhs.id == rhs.id
    }
}

struct PredefinedModels {
    static let models: [PredefinedModel] = [
        PredefinedModel(
            name: "ggml-tiny",
            displayName: "Tiny",
            size: "75 MiB",
            language: "Multilingual",
            description: "Tiny model, fastest, least accurate, supports multiple languages",
            speed: 0.95,
            accuracy: 0.6,
            ramUsage: 0.3,
            hash: "bd577a113a864445d4c299885e0cb97d4ba92b5f"
        ),
        PredefinedModel(
            name: "ggml-tiny.en",
            displayName: "Tiny (English)",
            size: "75 MiB",
            language: "English",
            description: "Tiny model optimized for English, fastest, least accurate",
            speed: 0.95,
            accuracy: 0.65,
            ramUsage: 0.3,
            hash: "c78c86eb1a8faa21b369bcd33207cc90d64ae9df"
        ),
        PredefinedModel(
            name: "ggml-base",
            displayName: "Base",
            size: "142 MiB",
            language: "Multilingual",
            description: "Base model, good balance of speed and accuracy, supports multiple languages",
            speed: 0.8,
            accuracy: 0.75,
            ramUsage: 0.5,
            hash: "465707469ff3a37a2b9b8d8f89f2f99de7299dac"
        ),
        PredefinedModel(
            name: "ggml-base.en",
            displayName: "Base (English)",
            size: "142 MiB",
            language: "English",
            description: "Base model optimized for English, good balance of speed and accuracy",
            speed: 0.8,
            accuracy: 0.8,
            ramUsage: 0.5,
            hash: "137c40403d78fd54d454da0f9bd998f78703390c"
        ),
        PredefinedModel(
            name: "ggml-small",
            displayName: "Small",
            size: "466 MiB",
            language: "Multilingual",
            description: "Small model, slower but more accurate than base, supports multiple languages",
            speed: 0.6,
            accuracy: 0.85,
            ramUsage: 0.7,
            hash: "55356645c2b361a969dfd0ef2c5a50d530afd8d5"
        ),
        PredefinedModel(
            name: "ggml-small.en",
            displayName: "Small (English)",
            size: "466 MiB",
            language: "English",
            description: "Small model optimized for English, slower but more accurate than base",
            speed: 0.6,
            accuracy: 0.9,
            ramUsage: 0.7,
            hash: "db8a495a91d927739e50b3fc1cc4c6b8f6c2d022"
        ),
        PredefinedModel(
            name: "ggml-medium",
            displayName: "Medium",
            size: "1.5 GiB",
            language: "Multilingual",
            description: "Medium model, slow but very accurate, supports multiple languages",
            speed: 0.4,
            accuracy: 0.92,
            ramUsage: 2.5,
            hash: "fd9727b6e1217c2f614f9b698455c4ffd82463b4"
        ),
        PredefinedModel(
            name: "ggml-medium.en",
            displayName: "Medium (English)",
            size: "1.5 GiB",
            language: "English",
            description: "Medium model optimized for English, slow but very accurate",
            speed: 0.4,
            accuracy: 0.95,
            ramUsage: 2.0,
            hash: "8c30f0e44ce9560643ebd10bbe50cd20eafd3723"
        ),
        PredefinedModel(
            name: "ggml-large-v3",
            displayName: "Large v3",
            size: "2.9 GiB",
            language: "Multilingual",
            description: "Large model v3, very slow but most accurate, supports multiple languages",
            speed: 0.2,
            accuracy: 0.98,
            ramUsage: 3.9,
            hash: "ad82bf6a9043ceed055076d0fd39f5f186ff8062"
        ),
        PredefinedModel(
            name: "ggml-large-v3-q5_0",
            displayName: "Large v3 (Quantized)",
            size: "1.1 GiB",
            language: "Multilingual",
            description: "Quantized version of Large v3, faster with slightly lower accuracy",
            speed: 0.3,
            accuracy: 0.97,
            ramUsage: 1.5,
            hash: "e6e2ed78495d403bef4b7cff42ef4aaadcfea8de"
        ),
        PredefinedModel(
            name: "ggml-large-v3-turbo",
            displayName: "Large v3 Turbo",
            size: "1.5 GiB",
            language: "Multilingual",
            description: "Large model v3 Turbo, faster than v3 with similar accuracy, supports multiple languages",
            speed: 0.5,
            accuracy: 0.97,
            ramUsage: 1.8,
            hash: "4af2b29d7ec73d781377bfd1758ca957a807e941"
        ),
        PredefinedModel(
            name: "ggml-large-v3-turbo-q5_0",
            displayName: "Large v3 Turbo (Quantized)",
            size: "547 MiB",
            language: "Multilingual",
            description: "Quantized version of Large v3 Turbo, faster with slightly lower accuracy",
            speed: 0.6,
            accuracy: 0.96,
            ramUsage: 1.0,
            hash: "e050f7970618a659205450ad97eb95a18d69c9ee"
        )
    ]
}
