import SwiftData

public enum RomsBoxModelContainer {
    /// The app's on-disk store, in the default SwiftData application-support location.
    public static func makeDefault() throws -> ModelContainer {
        let schema = Schema(versionedSchema: RomsBoxSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema)
        return try ModelContainer(for: schema, migrationPlan: RomsBoxMigrationPlan.self, configurations: [configuration])
    }

    /// An ephemeral in-memory store for previews and tests.
    public static func makeInMemory() throws -> ModelContainer {
        let schema = Schema(versionedSchema: RomsBoxSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: RomsBoxMigrationPlan.self, configurations: [configuration])
    }
}
