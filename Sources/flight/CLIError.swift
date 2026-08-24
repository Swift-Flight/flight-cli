import Foundation

enum CLIError: Error, CustomStringConvertible {
    case invalidName(String, String)
    case unknownTier(String, available: [String])
    case destinationExists(String)
    case writeFailed(String, underlying: any Error)

    var description: String {
        switch self {
        case .invalidName(let name, let why):
            return "'\(name)' is not a usable project name: \(why)."
        case .unknownTier(let tier, let available):
            return "no template named '\(tier)'. Available: \(available.joined(separator: ", "))."
        case .destinationExists(let path):
            return "\(path) already exists. Choose another name, or pass --force to write into it."
        case .writeFailed(let path, let underlying):
            return "could not write \(path): \(underlying)"
        }
    }
}
