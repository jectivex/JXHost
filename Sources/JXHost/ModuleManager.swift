import JXBridge
import FairCore
import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

/// The manager for a local cache of individual refs (e.g. tags and branches for a ``HubModuleSource``) of a certain repository.
@MainActor public class ModuleManager<Source: ModuleSource> : ObservableObject where Source.Ref : NamedRef {
    /// All the available refs and their dates for the module
    @Published public var refs: [Source.RefInfo] = []

    /// All the local versions that have been downloaded. This will be (re-)populated by the `scanModuleFolder()` function.
    @Published public var localVersions: [Source.Ref: URL] = [:]

    /// The ModuleSource
    public let source: Source

    /// The currently-active version of the local module
    public let installedVersion: SemVer?

    /// The relative path to the remove module for resolving references
    public let relativePath: String?

    /// The base path to the local folder that will keep the ref downloads.
    public let localPath: URL

    /// The `FileManager` for operations on the local file system
    public let fileManager: FileManager = .default

    public init(source: Source, relativePath: String?, installedVersion: SemVer?, localPath: URL) {
        self.source = source
        self.installedVersion = installedVersion
        self.relativePath = relativePath
        self.localPath = localPath
    }

    /// Returns the most recent available version that is compatible with this version
    public var latestCompatableVersion: Source.RefInfo? {
        self.refs
            .filter { refInfo in
                refInfo.ref.semver?.minorCompatible(with: self.installedVersion ?? .max) == true
            }
            .sorting(by: \.ref.semver)
            .last
    }

    public func refreshModules() async {
        dbg("refreshing modules")
        do {
            self.refs = try await source.refs
            dbg("available refs:", refs.map(\.ref.name))
        } catch {
            dbg("error getting source:", error)
        }
    }

    /// The local extraction path for the given ref.
    ///
    /// This will be something like: `~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/Library/Application%20Support/github.com/Magic-Loupe/PetStore.git/`
    public func localRootPath(for ref: Source.Ref) -> URL {
        localPath
            .appendingPathComponent(ref.type, isDirectory: true)
            .appendingPathComponent(ref.name, isDirectory: true)
    }

    /// Downloads the archive for the given ref and extracts it, returning the URL root of the extracted file system.
    /// - Parameters:
    ///   - ref: the ref to download
    ///   - overwrite: whether to overwrite an existing folder
    /// - Returns: the local file URL to the extracted root folder
    @discardableResult public func downloadArchive(for ref: Source.Ref, overwrite: Bool) async throws -> URL {
        let localExpandURL = localRootPath(for: ref)
        if fileManager.fileExists(atPath: localExpandURL.path) == true {
            if overwrite {
                dbg("removing:", localExpandURL.path)
                try fileManager.removeItem(at: localExpandURL)
            } else {
                dbg("returning existing folder:", localExpandURL.path)
                return localExpandURL
            }
        }

        // regardless of whether we succeed, always re-scan the local versions
        defer { try? scanModuleFolder() }

        let url = self.source.archiveURL(for: ref)
        dbg("loading ref:", ref, url)
        let (localURL, response) = try await URLSession.shared.downloadFile(for: URLRequest(url: url))
        dbg("downloaded:", localURL, response.expectedContentLength)
        let progress: Progress? = nil // TODO
        try fileManager.unzipItem(at: localURL, to: localExpandURL, progress: progress, trimBasePath: true, overwrite: true)
        dbg("extracted to:", localExpandURL)
        return localExpandURL
    }

    /// Remove the local cached folder for the given ref.
    public func removeLocalFolder(for ref: Source.Ref) throws {
        let path = localRootPath(for: ref)
        dbg("removing folder:", path.path)
        try fileManager.removeItem(at: path)
        self.localVersions[ref] = nil
        // try scanModuleFolder() // no need to re-scan, since we updated the only ref that would have changed
    }

    public func localRootPathExists(for ref: Source.Ref) -> Bool {
        localVersions[ref] != nil
    }

    public func localDynamicPath(for ref: Source.Ref) -> URL? {
        self.relativePath.flatMap({ URL(string: $0, relativeTo: localRootPath(for: ref)) })
    }

    public func scanModuleFolder() throws {
        // remove existing cached folders
        var versions: [Source.Ref: URL] = [:]
        defer {
            if versions != self.localVersions {
                // update the versions if anything has changed
                self.localVersions = versions
            }
        }

        if self.fileManager.isDirectory(url: localPath) != true {
            return dbg("no folder at:", localPath.path)
        }

        let dir = { url in
            try self.fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        }

        for base in try dir(localPath) {
            for sub in try dir(base) {
                // the sub-folder will be the ref name: e.g., for "tag": "1.1.2", "2.3.4" and for "branch": "main", "develop", etc.
                let name = sub.lastPathComponent
                // we expect the top-level folders to be named for the `Kind` of ref: "branch" or "tag"
                if let ref = Source.Ref(type: base.lastPathComponent, name: name) {
                    //dbg("creating ref:", ref, "to:", sub)
                    versions[ref] = sub
                }
            }
        }
    }
}

/// A `ModuleManager` backed by a `HubModuleSource`
public typealias HubVersionManager = ModuleManager<HubModuleSource>

extension HubModuleSource {
    /// The local cache folder for the given hub module.
    ///
    /// Tagged versions will go into:
    /// `~/Library/Application Support/jxmodules/HUB/ORG/REPO.git/tag/TAG/`
    ///
    /// For example, DatePlanner v. `0.0.1` will be cached at:
    /// `~/Library/Application Support/jxmodules/github.com/Magic-Loupe/DatePlanner.git/tag/0.0.1/`
    ///
    /// Branch versions will be in:
    /// `~/Library/Application Support/jxmodules/github.com/Magic-Loupe/DatePlanner.git/branch/main/`
    public var localPath: URL {
        let repoURL = self.repository
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("jxmodules", isDirectory: true)
            .appendingPathComponent(repoURL.host ?? "host", isDirectory: true)
            .appendingPathComponent(repoURL.path, isDirectory: true)
    }

    @MainActor public func versionManager<Module : JXDynamicModule>(for module: Module.Type, host: JXHostBundle, refName: String?) -> ModuleManager<Self> {
        HubVersionManager(source: self, relativePath: Module.moduleRelativePath(for: host), installedVersion: refName.flatMap(SemVer.init(string:)), localPath: self.localPath)
    }
}

extension JXDynamicModule {
    /// This will take the module named "petstore", find the identifier in `Package.resolved` as https://github.com/Magic-Loupe/PetStore.git, then create `Sources/PetStore/jx/petstore`.
    ///
    /// ```
    /// {
    ///   "identity" : "petstore",
    ///   "kind" : "remoteSourceControl",
    ///   "location" : "https://github.com/Magic-Loupe/PetStore",
    ///   "state" : {
    ///     "revision" : "05e37741cec16db4ade85aea341b7b1b7002fd6e",
    ///     "version" : "0.4.0"
    ///   }
    /// }
    /// ```
    static func moduleRelativePath(for host: JXHostBundle) -> String? {
        // TODO: need to cache the Package.resolved somewhere so we don't re-load/re-parse it every time the view is reloaded
        guard let package = host.packages(for: namespace).first else {
            return nil
        }

        guard let url = URL(string: package.location) else {
            return nil
        }

        let repoName = url.deletingPathExtension().lastPathComponent // turn "https://github.com/Magic-Loupe/PetStore.git" into "Sources/PetStore/jx/petstore"
        return "Sources/" + repoName + "/" + Self.moduleRootPath + "/" + (package.identity ?? "")
    }

    /// Returns a HubSource for this module. The `remoteModuleSource` is expected to logically separate the `baseURL` and `relativePath` in a way the host container can resolve, which may involve deriving ``Ref``-specific URLs based on those components.
    ///
    /// If the module itself specifies a remote URL, then that will be used. Otherwise, the module name will be matched with the package identifier in the host bundle's `Package.resolved` and the repository URL foir that package will be used.
    public static func remoteHubSource(for host: JXHostBundle) throws -> HubModuleSource {
        // if the module explicitly specifies its remote URL, then use that
        if let remoteURL = Self.remoteModuleSource {
            return HubModuleSource(repository: remoteURL, host: host)
        }

        // otherwise look up this package's namespace in the resolved packages and use that
        if let remoteURL = host.packageLocationURL(for: namespace) {
            return HubModuleSource(repository: remoteURL, host: host)
        }

        dbg("unable to find namespace:", Self.namespace.string)
        throw NoModuleFoundError(identifier: Self.namespace.string)
    }

}

struct NoModuleFoundError : Error {
    let identifier: String
}
