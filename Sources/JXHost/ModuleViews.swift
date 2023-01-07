#if canImport(SwiftUI)
import SwiftUI
import JXPod
import JXBridge
import FairCore

/// A view that displays a sectioned list of navigation links to individual versions of a module.
public struct ModuleVersionsListView<V: View>: View {
    @State var allVersionsExpanded = false

    let appName: String
    /// The branches that should be shown
    let branches: [String]

    let developmentMode: Bool

    let strictMode: Bool

    let errorHandler: (Error) -> ()

    @EnvironmentObject var versionManager: HubVersionManager
    let viewBuilder: (JXContext) -> V

    public init(appName: String, branches: [String], developmentMode: Bool, strictMode: Bool, errorHandler: @escaping (Error) -> Void, viewBuilder: @escaping (JXContext) -> V) {
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
        .refreshable {
            versionManager.scanModuleFolder()
            await versionManager.refreshModules()
        }
        .task {
            versionManager.scanModuleFolder()
            await versionManager.refreshModules()
        }
    }

    func log(_ value: String) {
        dbg(value)
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

    func createContext(for ref: HubModuleSource.Ref?) -> JXContext {
        let loader: JXScriptLoader
        if let ref = ref, let baseURL = versionManager.localDynamicPath(for: ref) {
            loader = LocalScriptLoader(baseURL: baseURL)
        } else {
            loader = MonitoringScriptLoader(log: self.log)
        }
        let context = JXContext(configuration: .init(strict: self.strictMode, scriptLoader: loader, log: self.log))
        return context
    }

    func moduleVersionLink(ref: HubModuleSource.Ref?, date: Date?, latest: Bool = false) -> some View {
        let compatible = ref?.semver?.minorCompatible(with: versionManager.installedVersion ?? .max)
        return ModuleRefPresenterView(appName: appName, ref: ref, date: date, versionManager: versionManager, compatible: compatible, errorHandler: errorHandler) {
            viewBuilder(createContext(for: ref))
        }
        .swipeActions(edge: .leading, content: {
            // show either a remove or download button, depending on whether the ref is currently downloaded
            if let ref = ref {
                if versionManager.localRootPathExists(for: ref) {
                    Button() {
                        versionManager.removeLocalFolder(for: ref)
                    } label: {
                        Label("Remove", systemImage: "trash")
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
                        Label("Download", systemImage: "square.and.arrow.down.fill")
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
            //.labelStyle(CentreAlignedLabelStyle())
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

