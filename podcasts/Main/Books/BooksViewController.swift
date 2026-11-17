import PocketCastsUtils
import SwiftUI
import UIKit

final class BooksViewController: PCHostingController<BooksLibraryView> {
    private let presenter: BooksAuthenticationPresenter

    init() {
        let presenter = BooksAuthenticationPresenter()
        self.presenter = presenter
        super.init(rootView: BooksLibraryView(model: BooksLibraryModel(presenter: presenter)))
        title = L10n.booksTitle
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presenter.window = view.window
    }

    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
struct BooksLibraryView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject var model: BooksLibraryModel

    var body: some View {
        List {
            if let name = model.downloadingName {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(name).font(.headline)
                        if model.validating { ProgressView(L10n.booksValidating) }
                        else { ProgressView(value: model.progress) }
                        Text(L10n.booksDownloadKeepOpen).font(.caption)
                        Button(L10n.cancel) { model.cancelDownload() }
                    }
                    .padding(.vertical, 8)
                }
            }
            if let title = model.addedTitle {
                Label(L10n.booksAddedToQueue(title), systemImage: "checkmark.circle.fill")
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if !model.downloads.isEmpty {
                Section(L10n.booksOnThisDevice) {
                    ForEach(model.downloads) { book in
                        Button { model.queue(book) } label: {
                            Label(book.title, systemImage: "text.badge.plus")
                        }
                    }
                }
            }
            Section {
                if model.connected {
                    if model.folders.count > 1 {
                        Button { Task { await model.back() } } label: {
                            Label(L10n.booksBackToLibrary, systemImage: "chevron.backward")
                        }
                    }
                    if model.loading { ProgressView(L10n.booksLoading) }
                    else if model.entries.isEmpty { Text(L10n.booksFolderEmpty) }
                    ForEach(model.entries) { entry in
                        if entry.kind == .folder {
                            Button { Task { await model.open(entry) } } label: {
                                HStack {
                                    Label(entry.name, systemImage: "folder")
                                    Spacer()
                                    Image(systemName: "chevron.forward").accessibilityHidden(true)
                                }
                            }
                        } else {
                            Button { model.select(entry) } label: {
                                HStack {
                                    Image(systemName: "arrow.down.circle").accessibilityHidden(true)
                                    VStack(alignment: .leading) {
                                        Text((entry.name as NSString).deletingPathExtension)
                                        if let size = entry.size, size <= UInt64(Int64.max) {
                                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)).font(.caption)
                                        }
                                    }
                                }
                            }
                            .disabled(model.downloadingName != nil)
                            .accessibilityHint(L10n.booksDownloadHint)
                        }
                    }
                    Button(L10n.booksRefresh) { Task { await model.refresh() } }
                        .disabled(model.loading)
                    Button(L10n.booksDisconnect) { Task { await model.disconnect() } }
                        .disabled(model.connecting)
                } else {
                    Label(L10n.booksLibraryTitle, systemImage: "books.vertical")
                        .font(.title2.bold())
                    Text(L10n.booksLibraryDescription)
                    if model.configuration != nil {
                        Button(L10n.booksConnect) { Task { await model.connect() } }
                            .disabled(model.connecting)
                        if model.connecting { ProgressView() }
                    } else { Text(L10n.booksConnectionPending) }
                }
            } header: {
                Text(model.folders.last?.title ?? L10n.booksLibraryTitle)
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
        .tint(AppTheme.color(for: .primaryInteractive01, theme: theme))
        .background(AppTheme.color(for: .primaryUi01, theme: theme))
        .task { await model.start() }
        .refreshable { await model.refresh() }
        .alert(L10n.booksTitle, isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(L10n.ok) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}
