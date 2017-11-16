import Foundation
import WordPressFlux

enum PluginAction: Action {
    case activate(id: String, siteID: Int)
    case deactivate(id: String, siteID: Int)
    case enableAutoupdates(id: String, siteID: Int)
    case disableAutoupdates(id: String, siteID: Int)
    case remove(id: String, siteID: Int)
    case receivePlugins(siteID: Int, plugins: SitePlugins)
    case receivePluginsFailed(siteID: Int, error: Error)
}

enum PluginQuery: Query {
    case all(siteID: Int)

    var siteID: Int {
        switch self {
        case .all(let siteID):
            return siteID
        }
    }
}

struct PluginStoreState {
    var plugins = [Int: SitePlugins]()
    var fetching = [Int: Bool]()
    var lastFetch = [Int: Date]()
}

class PluginStore: QueryStore<PluginStoreState, PluginQuery> {
    fileprivate let refreshInterval: TimeInterval = 60 // seconds

    init(dispatcher: Dispatcher = .global) {
        super.init(initialState: PluginStoreState(), dispatcher: dispatcher)
    }

    override func queriesChanged() {
        guard !activeQueries.isEmpty else {
            // Remove plugins from memory if nothing is listening for changes
            transaction({ (state) in
                state.plugins = [:]
                state.lastFetch = [:]
            })
            return
        }
        processQueries()
    }

    func processQueries() {
        let sitesWithQuery = activeQueries
            .map({ $0.siteID })
            .unique
        let sitesToFetch = sitesWithQuery
            .filter(shouldFetch(siteID:))

        sitesToFetch.forEach { (siteID) in
            fetchPlugins(siteID: siteID)
        }
    }

    override func onDispatch(_ action: Action) {
        guard let pluginAction = action as? PluginAction else {
            return
        }
        switch pluginAction {
        case .activate(let pluginID, let siteID):
            activatePlugin(pluginID: pluginID, siteID: siteID)
        case .deactivate(let pluginID, let siteID):
            deactivatePlugin(pluginID: pluginID, siteID: siteID)
        case .enableAutoupdates(let pluginID, let siteID):
            enableAutoupdatesPlugin(pluginID: pluginID, siteID: siteID)
        case .disableAutoupdates(let pluginID, let siteID):
            disableAutoupdatesPlugin(pluginID: pluginID, siteID: siteID)
        case .remove(let pluginID, let siteID):
            removePlugin(pluginID: pluginID, siteID: siteID)
        case .receivePlugins(let siteID, let plugins):
            receivePlugins(siteID: siteID, plugins: plugins)
        case .receivePluginsFailed(let siteID, _):
            state.fetching[siteID] = false
        }
    }
}

// MARK: - Selectors
extension PluginStore {
    func getPlugins(siteID: Int) -> SitePlugins? {
        return state.plugins[siteID]
    }

    func getPlugin(id: String, siteID: Int) -> PluginState? {
        return getPlugins(siteID: siteID)?.plugins.first(where: { $0.id == id })
    }

    func shouldFetch(siteID: Int) -> Bool {
        let lastFetch = state.lastFetch[siteID, default: .distantPast]
        let needsRefresh = lastFetch + refreshInterval < Date()
        let isFetching = state.fetching[siteID, default: false]
        return needsRefresh && !isFetching
    }
}

// MARK: - Action handlers
private extension PluginStore {
    func activatePlugin(pluginID: String, siteID: Int) {
        modifyPlugin(id: pluginID, siteID: siteID) { (plugin) in
            plugin.active = true
        }
        remote?.activatePlugin(
            pluginID: pluginID,
            siteID: siteID,
            success: {},
            failure: { [weak self] _ in
                self?.modifyPlugin(id: pluginID, siteID: siteID, change: { (plugin) in
                    plugin.active = false
                })
        })
    }

    func deactivatePlugin(pluginID: String, siteID: Int) {
        modifyPlugin(id: pluginID, siteID: siteID) { (plugin) in
            plugin.active = false
        }
        remote?.deactivatePlugin(
            pluginID: pluginID,
            siteID: siteID,
            success: {},
            failure: { [weak self] _ in
                self?.modifyPlugin(id: pluginID, siteID: siteID, change: { (plugin) in
                    plugin.active = true
                })
        })
    }

    func enableAutoupdatesPlugin(pluginID: String, siteID: Int) {
        modifyPlugin(id: pluginID, siteID: siteID) { (plugin) in
            plugin.autoupdate = true
        }
        remote?.enableAutoupdates(
            pluginID: pluginID,
            siteID: siteID,
            success: {},
            failure: { [weak self] _ in
                self?.modifyPlugin(id: pluginID, siteID: siteID, change: { (plugin) in
                    plugin.autoupdate = false
                })
        })
    }

    func disableAutoupdatesPlugin(pluginID: String, siteID: Int) {
        modifyPlugin(id: pluginID, siteID: siteID) { (plugin) in
            plugin.autoupdate = false
        }
        remote?.disableAutoupdates(
            pluginID: pluginID,
            siteID: siteID,
            success: {},
            failure: { [weak self] _ in
                self?.modifyPlugin(id: pluginID, siteID: siteID, change: { (plugin) in
                    plugin.autoupdate = true
                })
        })
    }

    func removePlugin(pluginID: String, siteID: Int) {
        guard let sitePlugins = state.plugins[siteID],
            let index = sitePlugins.plugins.index(where: { $0.id == pluginID }) else {
                return
        }
        state.plugins[siteID]?.plugins.remove(at: index)
        remote?.remove(
            pluginID: pluginID,
            siteID: siteID,
            success: {},
            failure: { [weak self] _ in
                _ = self?.getPlugins(siteID: siteID)
        })
    }

    func modifyPlugin(id: String, siteID: Int, change: (inout PluginState) -> Void) {
        guard let sitePlugins = state.plugins[siteID],
            let index = sitePlugins.plugins.index(where: { $0.id == id }) else {
                return
        }
        var plugin = sitePlugins.plugins[index]
        change(&plugin)
        state.plugins[siteID]?.plugins[index] = plugin
    }

    func fetchPlugins(siteID: Int) {
        guard let remote = remote else {
            return
        }
        state.fetching[siteID] = true
        remote.getPlugins(
            siteID: siteID,
            success: { [globalDispatcher] (plugins) in
                globalDispatcher.dispatch(PluginAction.receivePlugins(siteID: siteID, plugins: plugins))
            },
            failure: { [globalDispatcher] (error) in
                globalDispatcher.dispatch(PluginAction.receivePluginsFailed(siteID: siteID, error: error))
        })
    }

    func receivePlugins(siteID: Int, plugins: SitePlugins) {
        transaction { (state) in
            state.plugins[siteID] = plugins
            state.fetching[siteID] = false
            state.lastFetch[siteID] = Date()
        }
    }

    func receivePluginsFailed(siteID: Int) {
        transaction { (state) in
            state.fetching[siteID] = false
            state.lastFetch[siteID] = Date()
        }
    }

    private var remote: PluginServiceRemote? {
        let context = ContextManager.sharedInstance().mainContext
        let service = AccountService(managedObjectContext: context)
        guard let account = service.defaultWordPressComAccount() else {
            return nil
        }
        return PluginServiceRemote(wordPressComRestApi: account.wordPressComRestApi)
    }
}
