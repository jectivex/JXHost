import JXPod
import JXBridge
import FairApp
import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

/// The manager for a local cache of individual refs (e.g. tags and branches for a ``HubModuleSource``) of a certain repository.
@MainActor public class ModuleManager<Source: JXDynamicModuleSource> : ObservableObject where Source.Ref : NamedRef {
    /// All the available refs and their dates for the module
    @Published public var refs: [Source.RefInfo] = []

    /// All the local versions that have been downloaded. This will be (re-)populated by the `scanModuleFolder()` function.
    @Published public var localVersions: [Source.Ref: URL] = [:]

    /// The JXDynamicModuleSource
    public let source: Source

    /// The currently-active version of the local module
    public let installedVersion: SemVer?

    /// The relative path to the remove module for resolving references
    public let relativePath: String?

    /// The `FileManager` for operations on the local file system
    public let fileManager: FileManager

    /// The base path to the local folder that will keep the ref downloads.
    public let localPath: URL

    public init(source: Source, relativePath: String?, installedVersion: SemVer?, fileManager: FileManager = .default, localPath: URL) {
        self.source = source
        self.installedVersion = installedVersion
        self.relativePath = relativePath
        self.fileManager = fileManager
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

    @MainActor public func versionManager<Module : JXDynamicModule>(for module: Module.Type, host: Bundle, refName: String?) -> ModuleManager<Self> {
        HubVersionManager(source: self, relativePath: Module.moduleRelativePath(for: host), installedVersion: refName.flatMap(SemVer.init(string:)), localPath: self.localPath)
    }
}

extension JXDynamicModule {
    private static func package(for host: Bundle) throws -> ResolvedPackage.Package? {
        let resolved = try host.resolvedPackages().get()
        for package in resolved.packages {
            if Self.namespace.string == package.identity {
                return package
            }
        }
        return nil
    }

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
    static func moduleRelativePath(for host: Bundle) -> String? {
        // TODO: need to cache the Package.resolved somewhere so we don't re-load/re-parse it every time the view is reloaded
        guard let package = try? package(for: host) else {
            return nil
        }

        guard let url = URL(string: package.location) else {
            return nil
        }

        let repoName = url.deletingPathExtension().lastPathComponent // turn "https://github.com/Magic-Loupe/PetStore.git" into "Sources/PetStore/jx/petstore"
        return "Sources/" + repoName + "/" + Self.moduleRootPath + "/" + (package.identity ?? "")
    }

    public static func remoteModuleBaseURL(for host: Bundle) -> URL? {
        try? (package(for: host)?.location).flatMap(URL.init(string:))
    }
}

extension JXDynamicModule {
    /// Returns a HubSource for this module. The `remoteModuleSource` is expected to logically separate the `baseURL` and `relativePath` in a way the host container can resolve, which may involve deriving ``Ref``-specific URLs based on those components.
    ///
    /// If the module itself specifies a remote URL, then that will be used. Otherwise, the module name will be matched with the package identifier in the host bundle's `Package.resolved` and the repository URL foir that package will be used.
    public static func remoteHubSource(for bundle: Bundle) throws -> HubModuleSource {
        // if the module explicitly specifies its remote URL, then use that
        if let remoteURL = Self.remoteModuleBaseURL(for: bundle) {
            return try HubModuleSource(repository: remoteURL, host: bundle)
        }

        // guess the remote URL based on the Package.resolved of the host environment.
        guard let package = try? Self.package(for: bundle),
            let packageURL = URL(string: package.location) else {
            dbg("unable to find namespace:", Self.namespace.string)
            throw NoModuleFoundError(identifier: Self.namespace.string)
        }

        return try HubModuleSource(repository: packageURL, host: bundle)
    }

}

struct NoModuleFoundError : Error {
    let identifier: String
}

/// A module source that uses a git repository's tags and zipball archive URL for checking versions.
public struct HubModuleSource : JXDynamicModuleSource {
    // GitHub:
    //  repository: https://github.com/ORG/REPO.git
    //  tag list: https://github.com/ORG/REPO/tags.atom
    //  download: https://github.com/ORG/REPO/archive/refs/tags/TAG.zip
    //  download: https://github.com/ORG/REPO/archive/refs/heads/BRANCH.zip
    //   - redirects to: https://codeload.github.com/ORG/REPO/zip/refs/heads/BRANCH
    //   - e.g.: https://codeload.github.com/Magic-Loupe/AnimalFarm/zip/refs/heads/main

    // Gitea:
    //  repository: https://try.gitea.io/ORG/REPO.git
    //  tag list: https://try.gitea.io/ORG/REPO/tags.atom
    //  download: https://try.gitea.io/ORG/REPO/archive/TAG.zip

    // GitLab:
    //  repository: https://gitlab.com/ORG/REPO.git
    //  tag list: ???
    //  download: https://gitlab.com/ORG/REPO/-/archive/TAG/REPO-TAG.zip

    public let repository: URL // e.g., https://github.com/Magic-Loupe/PetStore.git

    /// The host bundle, which will be used to return the `Package.resolved`
    public let host: Bundle

    /// The resolved packages of the host environment, used for matching modules with their repositories
    public let resolvedPackages: ResolvedPackage

    public enum Ref : NamedRef {
        case tag(String)
        case branch(String)

        /// NamedRef initializer
        public init?(type: String, name: String) {
            guard let kind = Kind(rawValue: type) else {
                return nil
            }

            self.init(kind: kind, name: name)
        }

        /// Initialize with the given ref kind.
        public init(kind: Kind, name: String) {
            switch kind {
            case .tag: self = .tag(name)
            case .branch: self = .branch(name)
            }
        }

        /// The ref kind
        public enum Kind : String {
            case tag
            case branch
        }

        public var kind: Kind {
            switch self {
            case .tag: return .tag
            case .branch: return .branch
            }
        }

        /// Returns the tag or branch name
        public var type: String {
            kind.rawValue
        }

        /// Returns the tag or branch name
        public var name: String {
            switch self {
            case .tag(let str): return str
            case .branch(let str): return str
            }
        }

        /// If this is a tag and the string is a semantic version (e.g., 1.2.3), then return it.
        public var semver: SemVer? {
            guard case .tag = self else { return nil }
            return SemVer(string: self.name)
        }
    }

    public init(repository: URL, host: Bundle) throws {
        self.repository = repository
        self.host = host
        self.resolvedPackages = try host.resolvedPackages().get()
    }

    func url(_ relativeTo: String) -> URL {
        // convert "/PetStore.git" to "/PetStore"
        repository.deletingPathExtension().appendingPathComponent(relativeTo, isDirectory: false)
    }

    /// Returns true if the repository is managed by the given host
    func isHost(_ domain: String) -> Bool {
        ("." + (repository.host ?? "")).hasSuffix("." + domain)
    }

    /// Returns the URL for the zipball of the repository at the given tag or branch.
    /// - Parameters:
    ///   - name: the tag or branch name
    ///   - tag: whether the given name is for a tag or branch
    /// - Returns: the archive URL for the given named tag/branch
    public func archiveURL(for ref: Ref) -> URL {
        let name: String
        let tag: Bool
        switch ref {
        case .tag(let nm):
            name = nm
            tag = true
        case .branch(let nm):
            name = nm
            tag = false
        }

        if isHost("github.com") { // GitHub style
            // Tag: https://github.com/ORG/REPO/archive/refs/tags/TAG.zip
            // Branch: https://github.com/ORG/REPO/archive/refs/heads/BRANCH.zip
            return url("archive/refs")
                .appendingPathComponent(tag ? "tags" : "heads", isDirectory: true)
                .appendingPathComponent(name, isDirectory: false)
                .appendingPathExtension("zip")
        } else if isHost("gitlab.com") { // GitLab-style: same URL for branch and tag
            let repo = repository.pathComponents.dropFirst().first ?? "" // extract REPO from https://gitlab.com/ORG/REPO/…
            // Tag: https://gitlab.com/ORG/REPO/-/archive/TAG/REPO-TAG.zip
            // Branch: https://gitlab.com/ORG/REPO/-/archive/BRANCH/REPO-BRANCH.zip
            return url("-/archive")
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent(repo + "-" + name, isDirectory: false) // any name seems to work here, but the web UI names it repo-name.zip
                .appendingPathExtension("zip")
        } else { // Gitea-style: the same URL regardless of whether it is a branch or a tag
            // Tag: https://try.gitea.io/ORG/REPO/archive/TAG.zip
            // Branch: https://try.gitea.io/ORG/REPO/archive/BRANCH.zip
            return url("archive")
                .appendingPathComponent(name, isDirectory: false)
                .appendingPathExtension("zip")
        }
    }

    public var refs: [RefInfo] {
        get async throws {
            // TODO: this only works for GitHub … need to determine feed format for GitLab and Gitea, or use git to fetch tags
            let (data, _) = try await URLSession.shared.fetch(request: URLRequest(url: url("tags.atom")))
            let feed = try AtomFeed.parse(xml: data)
            return feed.feed.entry?.collectionMulti.map({ (Ref.tag($0.title), $0.updated) }) ?? []
        }
    }

    /// All the tags that can be parsed as a `SemVer`.
    public var tagVersions: [SemVer] {
        get async throws {
            try await refs.map(\.ref).compactMap(\.semver)
        }
    }
}

extension AtomFeed {
    /// Parses the given XML as an Atom feed
    static func parse(xml: Data) throws -> Self {
        try AtomFeed(jsum: XMLNode.parse(data: xml).jsum(), options: .init(dateDecodingStrategy: .iso8601))
    }
}

/// A minimal Atom feed implementation for parsing GitHub tag feeds like https://github.com/Magic-Loupe/PetStore/tags.atom
struct AtomFeed : Decodable {
    var feed: Feed

    struct Feed : Decodable {
        var id: String // tag:github.com,2008:https://github.com/Magic-Loupe/PetStore/releases
        var title: String
        var updated: Date

        /// The list of links, which when converted from XML might be translated as a single or multiple element
        typealias LinkList = ElementOrArray<Link> // i.e. XOr<Link>.Or<[Link]>
        var link: LinkList

        struct Link : Decodable {
            var type: String // text/html
            var rel: String // alternate
            var href: String // https://github.com/Magic-Loupe/PetStore/releases
        }

        /// The list of entries, which when converted from XML might be translated as a single or multiple element
        typealias EntryList = ElementOrArray<Entry> // i.e. XOr<Entry>.Or<[Entry]>
        var entry: EntryList?

        struct Entry : Decodable {
            var id: String // tag:github.com,2008:Repository/584868941/0.0.2
            var title: String // 0.0.2
            var updated: Date // "2023-01-03T20:28:34Z"
            var link: LinkList // https://github.com/Magic-Loupe/PetStore/releases/tag/0.0.2

//            var author: Author
//
//            struct Author : Decodable {
//                var name: String
//            }
//
//            var thumbnail: Thumbnail
//
//            struct Thumbnail : Decodable {
//                var height: String // 30
//                var width: String // 30
//                var url: URL // https://avatars.githubusercontent.com/u/659086?s=60&v=4
//            }
        }
    }
}
