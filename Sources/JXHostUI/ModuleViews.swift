///
/// Conditionl UI elements for selecting individual module versions
///
#if canImport(SwiftUI)
import SwiftUI
import JXBridge
import FairCore
@_exported import JXHost

extension JXDynamicModule {
    /// Creates a navigation link to a ``ModuleVersionsListView`` that will list all the available versions of a module.
    @MainActor @ViewBuilder public static func entryLink<V: View>(host: Bundle, name: String, symbol: String, branches: [String], developmentMode: Bool, strictMode: Bool, errorHandler: @escaping (Error) -> (), view: @escaping (JXContext) -> V) -> some View {
        let version = host.packageVersion(for: self.remoteModuleBaseURL(for: host))
        if let versionManager = (try? Self.remoteHubSource(for: host))?.versionManager(for: self, host: host, refName: version) {
            NavigationLink {
                ModuleVersionsListView(versionManager: versionManager, appName: name, branches: branches, developmentMode: developmentMode, strictMode: strictMode, errorHandler: errorHandler) { ctx in
                    view(ctx) // the root view that will be shown
                }
            } label: {
                HStack {
                    Label {
                        Text(name)
                    } icon: {
                        Image(systemName: symbol)
                    }
                    Spacer()
                    if let version = version {
                        Text(version)
                            .font(.caption.monospacedDigit())
                            .frame(alignment: .trailing)
                    }
                }
            }
        } else {
            Text("Unsupported hub source", bundle: .module, comment: "error marker for an unknown or unsupported source")
        }
    }
}

/// A view that displays a sectioned list of navigation links to individual versions of a module.
public struct ModuleVersionsListView<V: View>: View {
    public typealias Source = HubModuleSource // TODO: make generic
    @State var allVersionsExpanded = false
    private let appName: String
    private let branches: [String]
    private let developmentMode: Bool
    private let strictMode: Bool
    private let errorHandler: (Error) -> ()
    private let viewBuilder: (JXContext) -> V
    @ObservedObject private var versionManager: ModuleManager<Source>

    public init(versionManager: ModuleManager<Source>, appName: String, branches: [String], developmentMode: Bool, strictMode: Bool, errorHandler: @escaping (Error) -> Void, viewBuilder: @escaping (JXContext) -> V) {
        self.versionManager = versionManager
        self.appName = appName
        self.branches = branches
        self.developmentMode = developmentMode
        self.strictMode = strictMode
        self.errorHandler = errorHandler
        self.viewBuilder = viewBuilder
    }

    public var body: some View {
        List {
#if DEBUG
            if self.developmentMode == true {
                Section {
                    moduleVersionLink(ref: nil, date: nil)
                } header: {
                    Text("Live", bundle: .module, comment: "section header title for apps list view live edit section")
                }
            }
#endif

            Section {
                if let latestRef = versionManager.latestCompatableVersion {
                    moduleVersionLink(ref: .tag(latestRef.ref.name), date: latestRef.date, latest: true)
                }

                if self.developmentMode == true {
                    DisclosureGroup(isExpanded: $allVersionsExpanded) {
                        ForEach(versionManager.refs, id: \.ref.name) { refDate in
                            moduleVersionLink(ref: refDate.ref, date: refDate.date)
                        }
                    } label: {
                        Text("All Versions (\(versionManager.refs.count, format: .number))", bundle: .module, comment: "header title for disclosure group listing versions")
                    }
                }

            } header: {
                Text("Versions", bundle: .module, comment: "section header title for apps list view live edit section")
            }

            if self.developmentMode == true, branches.isEmpty == false {
                Section {
                    ForEach(branches, id: \.self) { branch in
                        moduleVersionLink(ref: .branch(branch), date: nil)
                    }
                } header: {
                    Text("Branches", bundle: .module, comment: "section header title for apps list view branches section")
                }
            }
        }
        .navigationTitle(appName)
        .refreshable { await refreshModules() }
        .task { await refreshModules() }
    }

    func refreshModules() async {
        do {
            try versionManager.scanModuleFolder()
            await versionManager.refreshModules()
        } catch {
            errorHandler(error)
        }
    }

    func log(_ value: String) {
        dbg(value)
        // errorHandler(NSError(domain: "JS", code: 0, userInfo: [NSLocalizedDescriptionKey: value])) // enters loop
    }

    struct LocalScriptLoader : JXScriptLoader {
        let baseURL: URL

        func scriptURL(resource: String, relativeTo: URL?, root: URL) throws -> URL {
            // we ignore the passed-in root and instead use our own base URL
            // let url = URL(fileURLWithPath: resource, relativeTo: self.baseURL) // relative doesn't seem to work
            let url = baseURL.appendingPathComponent(resource)
            dbg("resolved:", resource, "as:", url.path)
            return url
        }

        func loadScript(from url: URL) throws -> String? {
            //dbg(url.absoluteString)
            return try String(contentsOf: url)
        }
    }

    @MainActor func createContext(for ref: Source.Ref?) -> JXContext {
        let loader: JXScriptLoader
        if let ref = ref, let baseURL = versionManager.localDynamicPath(for: ref) {
            loader = LocalScriptLoader(baseURL: baseURL)
        } else {
            loader = MonitoringScriptLoader(log: { self.log($0) })
        }
        let context = JXContext(configuration: .init(strict: self.strictMode, scriptLoader: loader, log: { self.log($0) }))
        return context
    }

    @MainActor func moduleVersionLink(ref: Source.Ref?, date: Date?, latest: Bool = false) -> some View {
        let compatible = ref?.semver?.minorCompatible(with: versionManager.installedVersion ?? .max)
        return ModuleRefPresenterView(appName: appName, ref: ref, date: date, versionManager: versionManager, compatible: compatible, errorHandler: errorHandler) {
            viewBuilder(createContext(for: ref))
        }
        .swipeActions(edge: .leading, content: {
            // show either a remove or download button, depending on whether the ref is currently downloaded
            if let ref = ref {
                if versionManager.localRootPathExists(for: ref) {
                    Button() {
                        do {
                            try versionManager.removeLocalFolder(for: ref)
                        } catch {
                            dbg("error removing local folder for:", ref, error)
                            errorHandler(error)
                        }
                    } label: {
                        Label {
                            Text("Remove", bundle: .module, comment: "button text for action to remove a downloaded ref")
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                    .tint(.red)
                } else {
                    Button() {
                        Task {
                            do {
                                try await versionManager.downloadArchive(for: ref, overwrite: true)
                            } catch {
                                dbg(error)
                                errorHandler(error)
                            }
                        }
                    } label: {
                        Label {
                            Text("Download", bundle: .module, comment: "button text for action to download a ref")
                        } icon: {
                            Image(systemName: "square.and.arrow.down.fill")
                        }
                    }
                    .tint(.yellow)
                }
            }
        })
        .disabled(compatible == false)
    }
}

struct ModuleRefPresenterView<V: View>: View {
    let appName: String
    let ref: HubModuleSource.Ref?
    let date: Date?
    let versionManager: HubVersionManager
    let compatible: Bool?
    let errorHandler: (Error) -> ()
    let viewBuilder: () -> V

    @State var isPresented = false

    var body: some View {
        Button(action: { isPresented = true }) {
            Label {
                VStack(alignment: .leading) {
                    //Text(appName)
                    HStack {
                        // if latest == true {
                        //     Text("Latest", bundle: .module, comment: "prefix for string that is the most recent string")
                        // }
                        if let ref = ref {
                            Text(ref.name)
                        } else {
                            Text(appName)
                        }
                        Spacer()
                        if let date = date {
                            Text("\(date, format: .relative(presentation: .named, unitsStyle: .abbreviated))", bundle: .module, comment: "list comment title describing the current version")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    //.font(.footnote.monospacedDigit())
                }
            } icon: {
                iconView()
            }
            .frame(alignment: .center)
        }
        .sheet(isPresented: $isPresented) {
            ModuleRefView(ref: ref, errorHandler: errorHandler) { viewBuilder() }
                .environmentObject(versionManager)
        }
    }

    @MainActor func iconView() -> Image {
        if let version = ref {
            if version.name == versionManager.installedVersion?.versionString {
                return Image(systemName: "circle.inset.filled")
            } else if compatible == false {
                return Image(systemName: "xmark.circle") // unavailable
            } else if versionManager.localRootPathExists(for: version) {
                return Image(systemName: "circle.dashed.inset.filled")
            } else {
                return Image(systemName: "circle.dashed")
            }
        } else {
            // no version: using local file system
            return Image(systemName: "arrow.clockwise.circle.fill")
        }
    }
}

struct ModuleRefView<Content: View> : View {
    let ref: HubModuleSource.Ref?
    let errorHandler: (Error) -> ()
    let content: () -> Content
    @EnvironmentObject var versionManager: HubVersionManager
    @State var loading: Bool = true

    var body: some View {
        if loading == true {
            ProgressView()
                .task(id: ref, { await loadRef(overwrite: true) })
        } else {
            content()
        }
    }

    @discardableResult func loadRef(overwrite: Bool) async -> URL? {
        defer {
            loading = false
        }

        guard let ref = ref else {
            dbg("no ref to load")
            return nil
        }

        do {
            return try await versionManager.downloadArchive(for: ref, overwrite: overwrite)
        } catch {
            errorHandler(error)
            return nil
        }
    }
}
#endif

