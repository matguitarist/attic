import Testing
@testable import AtticScraping
import AtticModels

/// ScreenScraper's own systems for each board (checked on its system
/// pages), not MAME's catch-all 75.
@Test func arcadeBoardsHaveTheirOwnScreenScraperSystems() {
    let expected: [CanonicalSystemID: Int] = [
        .naomi: 56, .naomi2: 230, .naomigd: 227, .atomiswave: 53,
        .model2: 54, .model3: 55, .stv: 69, .gaelco: 194,
        .n64dd: 122, .satellaview: 107, .sufami: 108,
    ]
    for (system, id) in expected {
        #expect(ScreenScraperSystemID.systemeID(for: system) == id, "\(system.rawValue)")
    }
}
