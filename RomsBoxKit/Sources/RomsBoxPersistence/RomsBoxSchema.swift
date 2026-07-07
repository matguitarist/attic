import SwiftData

/// Adopted from day one, even with a single version, so a future field
/// change doesn't require a painful retrofit of migration infrastructure.
public enum RomsBoxSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [GameSystem.self, Game.self, EmulatorProfile.self, PlaySession.self]
    }
}

public enum RomsBoxMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [RomsBoxSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
