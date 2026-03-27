import Foundation

enum Pose: Int, CaseIterable, Codable, Identifiable {
    case front = 0
    case side = 1
    case back = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .front: "Front"
        case .side: "Side"
        case .back: "Back"
        }
    }

    var instruction: String {
        switch self {
        case .front: "Face the camera. Stand tall, arms relaxed at your sides."
        case .side: "Turn to your left side. Keep your arms relaxed."
        case .back: "Turn away from the camera. Stand tall, arms at your sides."
        }
    }

    var audioPrompt: String {
        switch self {
        case .front: "Face the camera. Stand tall with your arms relaxed at your sides."
        case .side: "Now turn to your left side. Keep your arms relaxed at your sides."
        case .back: "Turn away from the camera. Stand tall with your arms relaxed."
        }
    }

    var next: Pose? {
        Pose(rawValue: rawValue + 1)
    }

    var stepNumber: Int {
        rawValue + 1
    }
}
