import FairApp
@_exported import JXKit
@_exported import JXBridge

extension Bundle {
    func findVersion(repository: URL?, in packages: [(url: String, version: String?)]) -> String? {
        for (url, version) in packages {
            // note that some repositories have the ".git" extension and some do not; compare them by trimming the extension
            if url == repository?.absoluteString
                || url == repository?.deletingPathExtension().absoluteString {
                // the package matches, so return the version, which might be a
                //dbg("package version found for", repository, version)
                return version
            }
        }

        //dbg("no package version found for", repository)
        return nil
    }

    /// Returns the version of the package from the "Package.resolved" that is bundled with this app.
    func packageVersion(for repository: URL?) -> String? {
        do {
            let resolved = try ResolvedPackage(json: self.loadResource(named: "Package.resolved"))
            let resolvedVersion: String?
            switch resolved.rawValue {
                // handle both versions of the resolved package format
            case .p(let v1):
                resolvedVersion = findVersion(repository: repository, in: v1.object.pins.map({ ($0.repositoryURL, $0.state.version) }))
            case .q(let v2):
                resolvedVersion = findVersion(repository: repository, in: v2.pins.map({ ($0.location, $0.state.version) }))
            }

            dbg(repository, "resolvedVersion:", resolvedVersion)
            return resolvedVersion
        } catch {
            dbg("error getting package version for", repository, error)
            return nil
        }

    }
}
