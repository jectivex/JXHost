import FairApp
@_exported import JXKit
@_exported import JXBridge

extension Bundle {
    func findVersion(repository: URL?, in resolved: ResolvedPackage) -> ResolvedPackage.Package? {
        for version in resolved.packages {
            // note that some repositories have the ".git" extension and some do not; compare them by trimming the extension
            if version.location == repository?.absoluteString
                || version.location == repository?.deletingPathExtension().absoluteString {
                // the package matches, so return the version, which might be a
                //dbg("package version found for", repository, version)
                return version
            }
        }

        dbg("no package version found for", repository)
        return nil
    }

    /// Returns the version of the package from the "Package.resolved" that is bundled with this app.
    public func packageVersion(for repository: URL?) -> String? {
        do {
            let resolved = try self.resolvedPackages().get()
            let resolvedVersion = findVersion(repository: repository, in: resolved)
            dbg(repository, "resolvedVersion:", resolvedVersion)
            return resolvedVersion?.state.version
        } catch {
            dbg("error getting package version for", repository, error)
            return nil
        }

    }
}
