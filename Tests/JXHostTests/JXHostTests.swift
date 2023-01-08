import XCTest
@testable import JXHost

final class JXHostTests: XCTestCase {
    func testHosting() async throws {
        let source = HubModuleSource(repository: URL(string: "https://github.com/Magic-Loupe/PetStore.git")!)
        let refs = try await source.refs
        XCTAssertGreaterThanOrEqual(refs.count, 10)
        let version = try XCTUnwrap(refs.first).ref
        let tmp = URL(fileURLWithPath: UUID().uuidString, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory()))
        let manager = await HubVersionManager(source: source, relativePath: "XXX", installedVersion: nil, localPath: tmp)
        let downloaded = try await manager.downloadArchive(for: version, overwrite: true)

    }
}
