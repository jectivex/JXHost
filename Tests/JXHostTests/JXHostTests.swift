import XCTest
@testable import JXHost

final class JXHostTests: XCTestCase {
    func testAtomFeed() async throws {
    }

    func testHosting() async throws {
        // provide enough of a fake Package.resolved to be able to look up the repo and version
        let source = try HubModuleSource(repository: URL(string: "https://github.com/Magic-Loupe/PetStore.git")!, host: JXHostBundle(bundle: .module, packages: .init(json: """
        {
          "pins" : [
            {
              "identity" : "petstore",
              "kind" : "remoteSourceControl",
              "location" : "https://github.com/Magic-Loupe/PetStore",
              "state" : {
                "revision" : "05e37741cec16db4ade85aea341b7b1b7002fd6e",
                "version" : "0.4.0"
              }
            }
          ],
          "version" : 2
        }
        """.utf8Data)))
        let refs = try await source.refs
        XCTAssertGreaterThanOrEqual(refs.count, 10)
        let version = try XCTUnwrap(refs.first).ref
        let tmp = URL(fileURLWithPath: UUID().uuidString, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory()))
        let manager = await HubVersionManager(source: source, relativePath: nil, installedVersion: nil, localPath: tmp)
        let downloaded = try await manager.downloadArchive(for: version, overwrite: true)
        print("downloaded:", downloaded)
        let path = URL(fileURLWithPath: "Sources/PetStore/jx/petstore", relativeTo: downloaded)
        XCTAssertEqual(true, path.pathIsDirectory)
    }
}
