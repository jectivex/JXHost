import XCTest
@testable import JXHost

final class JXHostTests: XCTestCase {
    func testHosting() async throws {
        let source = HubModuleSource(repository: URL(string: "https://github.com/Magic-Loupe/PetStore.git")!)
        let refs = try await source.refs
        XCTAssertGreaterThanOrEqual(refs.count, 10)
    }
}
