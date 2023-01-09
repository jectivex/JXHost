import Foundation
import JXBridge
import JXKit
import FairCore

/// The source repository that hosts the tagged versions of the dynamic module source.
public protocol ModuleSource {
    /// A reference to a version of the module, which can then be converted into an archive URL
    associatedtype Ref

    /// Information about the tags for the given module source
    typealias RefInfo = (ref: Ref, date: Date)

    /// The available refs for this module source
    var refs: [RefInfo] { get async throws }

    /// Returns the URL for the zipball of the repository at the given tag or branch.
    /// - Parameters:
    ///   - ref: the ref for the archive
    /// - Returns: the archive URL for the given named ref
    func archiveURL(for ref: Ref) -> URL
}


/// A Ref that has a name and type that can be converted into a String
public protocol NamedRef : Hashable {
    var name: String { get }
    var type: String { get }

    /// Create this ref with the given type and name.
    init?(type: String, name: String)
}

extension NamedRef {
    /// Attempts to parse the name as a semantic version (e.g., `1.2.3`).
    public var semver: SemVer? {
        SemVer(rawValue: name)
    }
}
