import JXBridge
import FairCore
import Foundation

/// A module source that uses a git repository's tags and zipball archive URL for checking versions.
public struct HubModuleSource : ModuleSource {
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

    public init(repository: URL, host: JXHostBundle) {
        self.repository = repository
        self.resolvedPackages = host.resolved
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
private struct AtomFeed : Decodable {
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
