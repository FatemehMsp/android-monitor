import SwiftUI

struct AppsPanel: View {
    @StateObject private var model: AppsModel
    @State private var query = ""
    @State private var filter = Filter.user
    @State private var selection: String?

    enum Filter: String, CaseIterable { case user = "User", system = "System", debuggable = "Debuggable", all = "All" }

    init(serial: String) { _model = StateObject(wrappedValue: AppsModel(serial: serial)) }

    private var shown: [PhoneApp] {
        model.apps.filter { app in
            switch filter {
            case .user: return !app.isSystem
            case .system: return app.isSystem
            case .debuggable: return app.isDebuggable
            case .all: return true
            }
        }.filter { query.isEmpty || $0.label.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search apps", text: $query).textFieldStyle(.roundedBorder)
                Picker("", selection: $filter) { ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.menu).frame(width: 110).labelsHidden()
                Button { model.load() } label: { Image(systemName: "arrow.clockwise") }.help("Reload")
                Button { model.install() } label: { Label("Install APK", systemImage: "plus.app") }
            }
            .padding(10)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(shown) { app in
                        AppTile(app: app, selected: selection == app.id)
                            .onTapGesture(count: 2) { model.launch(app) }
                            .onTapGesture { selection = app.id }
                            .contextMenu {
                                Button("Launch") { model.launch(app) }
                                Button("Force stop") { model.stop(app) }
                                Button("App info") { model.info(app) }
                                Divider()
                                Button("Save APK…") { model.pullAPK(app) }
                                Button("Clear data…") { model.clearData(app) }
                                Button("Uninstall…", role: .destructive) { model.uninstall(app) }
                            }
                    }
                }
                .padding(10)
            }
            HStack(spacing: 8) {
                if model.loading { ProgressView().controlSize(.small) }
                Text(model.message ?? "\(shown.count) apps · double-click to launch · right-click for more")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }
            .padding(8)
        }
        .onAppear { if model.apps.isEmpty { model.load() } }
    }
}

private struct AppTile: View {
    let app: PhoneApp
    let selected: Bool
    var body: some View {
        Card(selected: selected) {
            HStack(spacing: 10) {
                Group {
                    if let icon = app.icon { Image(nsImage: icon).resizable().interpolation(.high) }
                    else { Image(systemName: "app.fill").resizable().foregroundStyle(.secondary) }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.label).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(app.id).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 4) {
                        if !app.version.isEmpty { Text(app.version).font(.system(size: 9)).foregroundStyle(.secondary) }
                        if app.isDebuggable { Text("DEBUG").font(.system(size: 8, weight: .bold)).padding(.horizontal, 4).background(Color.orange.opacity(0.85), in: Capsule()).foregroundStyle(.black) }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
