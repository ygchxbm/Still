import Foundation

struct StateFileStorage {
    let file: URL
    let writeData: (Data, URL) throws -> Void

    func load() throws -> SavedState? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: file))
        try state.validate()
        return state
    }

    func save(_ state: SavedState, preservingLegacyFile: Bool) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if preservingLegacyFile {
            let backup = file.appendingPathExtension("v1-backup")
            if !manager.fileExists(atPath: backup.path) { try manager.copyItem(at: file, to: backup) }
        }
        let data = try JSONEncoder().encode(state)
        try writeData(data, file)
    }
}
