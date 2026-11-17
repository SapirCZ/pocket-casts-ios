import PocketCastsUtils
import PocketCastsDataModel
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
    @State private var query = ""
    @State private var downloadedOnly = false

    private var secondary: Color { AppTheme.color(for: .primaryText02, theme: theme) }
    private var surface: Color { AppTheme.color(for: .primaryUi02, theme: theme) }
    private var accent: Color { AppTheme.color(for: .primaryInteractive01, theme: theme) }
    private let columns = [GridItem(.adaptive(minimum: 135, maximum: 220), spacing: 24, alignment: .top)]

    private var filteredEntries: [DropboxLibraryEntry] {
        model.entries.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
    }

    private var filteredDownloads: [PersonalBook] {
        model.downloads.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                libraryHeader
                if let name = model.downloadingName { downloadProgress(name) }
                if let title = model.addedTitle {
                    Label(L10n.booksAddedToQueue(title), systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium)).foregroundStyle(accent)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if !downloadedOnly, query.isEmpty, let book = model.downloads.first { readyBook(book) }
                if !model.connected, !downloadedOnly { connectionCard }
                if model.connected || !model.downloads.isEmpty {
                    searchAndFilters
                    if downloadedOnly { downloadedGrid }
                    else { remoteGrid }
                }
            }
            .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 30)
        }
        .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
        .tint(accent)
        .background(AppTheme.color(for: .primaryUi01, theme: theme))
        .task { await model.start() }
        .refreshable { await model.refresh() }
        .alert(L10n.booksTitle, isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(L10n.ok) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(downloadedOnly ? L10n.booksOnThisDevice : BooksArtwork.title(model.folders.last?.title ?? L10n.booksLibraryTitle))
                    .font(.system(model.folders.count > 1 && !downloadedOnly ? .title2 : .largeTitle, design: .serif, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if model.connected {
                    Menu {
                        Label(L10n.booksDropboxConnected, systemImage: "checkmark.icloud")
                        Button(L10n.booksRefresh, systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                        Button(L10n.booksDisconnect, systemImage: "rectangle.portrait.and.arrow.right") { Task { await model.disconnect() } }
                    } label: { Image(systemName: "ellipsis.circle").font(.title3).padding(8) }
                    .accessibilityLabel(L10n.booksLibraryOptions)
                }
            }
            if model.folders.count > 1, !downloadedOnly {
                Button { Task { await model.back() } } label: {
                    Label(L10n.booksBackToLibrary, systemImage: "chevron.backward").font(.subheadline)
                }.padding(.top, 4)
            }
        }
    }

    private var searchAndFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(secondary)
                TextField(L10n.booksSearchLibrary, text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(secondary) }
                        .accessibilityLabel(L10n.booksClearSearch)
                }
            }.padding(14).background(surface, in: RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 10) {
                filterButton(L10n.booksAll, selected: !downloadedOnly) { downloadedOnly = false }
                filterButton(L10n.booksOnThisDevice, selected: downloadedOnly) { downloadedOnly = true }
            }
        }
    }

    private func filterButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 10)
                .foregroundStyle(selected ? accent : secondary)
                .background(selected ? accent.opacity(0.14) : surface, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var remoteGrid: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.loading { ProgressView(L10n.booksLoading).frame(maxWidth: .infinity).padding(30) }
            else if filteredEntries.isEmpty { emptyShelf(model.entries.isEmpty ? L10n.booksFolderEmpty : L10n.booksSearchEmpty) }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                ForEach(filteredEntries) { entry in
                    BooksShelfCard(title: BooksArtwork.title(entry.name), subtitle: subtitle(entry), collection: entry.kind == .folder,
                                   downloaded: model.downloads.contains { $0.fileID == entry.id }, artwork: { await model.artwork(for: entry) }) {
                        if entry.kind == .folder { query = ""; Task { await model.open(entry) } }
                        else { model.select(entry) }
                    }
                    .disabled(entry.kind == .file && model.downloadingName != nil)
                }
            }
        }
    }

    private var downloadedGrid: some View {
        VStack {
            if filteredDownloads.isEmpty { emptyShelf(query.isEmpty ? L10n.booksNoDownloads : L10n.booksSearchEmpty) }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                ForEach(filteredDownloads) { book in
                    BooksShelfCard(title: BooksArtwork.title(book.fileName), subtitle: L10n.booksOfflineReady, collection: false, downloaded: true,
                                   artwork: { await model.artwork(for: book) }) { model.queue(book) }
                }
            }
        }
    }

    private func subtitle(_ entry: DropboxLibraryEntry) -> String {
        if entry.kind == .folder { return L10n.booksCollection }
        if let size = entry.size, size <= UInt64(Int64.max) { return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }
        return L10n.booksAudiobook
    }

    private func emptyShelf(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical").font(.largeTitle)
            Text(message).font(.subheadline).multilineTextAlignment(.center)
        }.foregroundStyle(secondary).frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func readyBook(_ book: PersonalBook) -> some View {
        BooksReadyCard(book: book, artwork: { await model.artwork(for: book) }) { model.queue(book) }
    }

    private func downloadProgress(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(BooksArtwork.title(name), systemImage: "arrow.down.circle").font(.headline)
            if model.validating { ProgressView(L10n.booksValidating) }
            else { ProgressView(value: model.progress) }
            HStack(alignment: .top) {
                Text(L10n.booksDownloadKeepOpen).font(.caption).foregroundStyle(secondary)
                Spacer()
                Button(L10n.cancel) { model.cancelDownload() }.font(.subheadline)
            }
        }.padding(18).background(surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "books.vertical").font(.largeTitle).foregroundStyle(accent)
            Text(L10n.booksLibraryDescription).font(.body).foregroundStyle(secondary)
            if model.configuration != nil {
                Button(L10n.booksConnect) { Task { await model.connect() } }
                    .buttonStyle(.borderedProminent).disabled(model.connecting)
                if model.connecting { ProgressView() }
            } else { Text(L10n.booksConnectionPending) }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(surface, in: RoundedRectangle(cornerRadius: 22))
    }
}
