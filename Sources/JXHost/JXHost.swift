import FairApp
@_exported import JXKit
@_exported import JXBridge

public struct JXHost {
    public init() {
    }
}

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
    func packageVersion(host bundle: Bundle?, for repository: URL?) -> String? {
        dbg(repository)
        do {
            let resolved = try ResolvedPackage(json: (bundle ?? Bundle.module).loadResource(named: "Package.resolved"))
            switch resolved.rawValue {
                // handle both versions of the resolved package format
            case .p(let v1):
                return findVersion(repository: repository, in: v1.object.pins.map({ ($0.repositoryURL, $0.state.version) }))
            case .q(let v2):
                return findVersion(repository: repository, in: v2.pins.map({ ($0.location, $0.state.version) }))
            }
        } catch {
            dbg("error getting package version for", repository, error)
            return nil
        }

    }
}


#if canImport(SwiftUI)
@_exported import JXSwiftUI
@_exported import SwiftUI

extension JXDynamicModule {
    @MainActor @ViewBuilder public static func entryLink<V: View>(host: Bundle?, name: String, symbol: String, branches: [String], developmentMode: Bool, strictMode: Bool, errorHandler: @escaping (Error) -> (), view: @escaping (JXContext) -> V) -> some View {
        let version = host?.packageVersion(host: host, for: Self.remoteURL.baseURL)
        let source = Self.hubSource
        NavigationLink {
            ModuleVersionsListView(versionManager: source.versionManager(for: self, refName: version), appName: name, branches: branches, developmentMode: developmentMode, strictMode: strictMode, errorHandler: errorHandler) { ctx in
                view(ctx) // the root view that will be shown
            }
        } label: {
            HStack {
                Label {
                    Text(name)
                } icon: {
                    Image(systemName: symbol)
                    //.symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                }
                Spacer()
                Text(version ?? "")
                    .font(.caption.monospacedDigit())
                    .frame(alignment: .trailing)
            }
        }
    }
}
#endif
