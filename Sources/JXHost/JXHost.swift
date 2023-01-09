import Foundation
import FairCore
@_exported import JXKit
@_exported import JXBridge


/// A host environment for a JXModule, which contains about the Bundle environment as well as the resolved packages for the bundle.
public class JXHostBundle {
    public let bundle: Bundle
    public let resolved: ResolvedPackage

    public init(bundle: Bundle) throws {
        self.bundle = bundle
        self.resolved = try bundle.resolvedPackages().get()
    }

    public init(bundle: Bundle, packages resolved: ResolvedPackage) {
        self.bundle = bundle
        self.resolved = resolved
    }
}

extension JXHostBundle {
    /// Returns the package that matches the give namespace.
    ///
    /// This merely compares the namespace against the package's `identifier`, which defaults to the lower-case package name,
    internal func packages(for namespace: JXNamespace) -> [ResolvedPackage.Package] {
        resolved.packages.filter({ $0.identity == namespace.string })
    }

    /// Returns the version of the package from the "Package.resolved" that is bundled with this app.
    public func packageVersion(for namespace: JXNamespace) -> String? {
        packages(for: namespace).first?.state.version
    }

    public func packageLocationURL(for namespace: JXNamespace) -> URL? {
        packages(for: namespace).first?.locationURL
    }
}

extension ResolvedPackage.Package {
    var locationURL: URL? {
        URL(string: location)
    }
}
