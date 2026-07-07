import Foundation
import SwiftData
import RomsBoxModels

@Model
public final class EmulatorProfile {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var executablePath: String
    /// May contain `{romPath}` / `{romDir}` / `{romName}` / `{romNameNoExt}`
    /// placeholders, substituted at launch time (RomsBoxEmulation, Phase 8).
    public var argumentTemplate: String
    public var workingDirectoryPath: String?
    public var assignedSystemIDRawValues: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        executableURL: URL,
        argumentTemplate: String,
        workingDirectoryURL: URL? = nil,
        assignedSystemIDs: [CanonicalSystemID] = []
    ) {
        self.id = id
        self.name = name
        self.executablePath = executableURL.path
        self.argumentTemplate = argumentTemplate
        self.workingDirectoryPath = workingDirectoryURL?.path
        self.assignedSystemIDRawValues = assignedSystemIDs.map(\.rawValue)
    }
}

extension EmulatorProfile {
    public var executableURL: URL { URL(fileURLWithPath: executablePath) }
    public var workingDirectoryURL: URL? { workingDirectoryPath.map { URL(fileURLWithPath: $0) } }
    public var assignedSystemIDs: [CanonicalSystemID] {
        get { assignedSystemIDRawValues.map { CanonicalSystemID($0) } }
        set { assignedSystemIDRawValues = newValue.map(\.rawValue) }
    }
}
