import PocketCastsDataModel
import PocketCastsUtils
import SwiftUI

struct BooksCoverView: View {
    let title: String
    var collection = false
    var image: UIImage?

    private var coverColor: Color {
        let colors: [Color] = [Color(red: 0.22, green: 0.35, blue: 0.38), Color(red: 0.4, green: 0.26, blue: 0.34), Color(red: 0.52, green: 0.35, blue: 0.24), Color(red: 0.27, green: 0.4, blue: 0.33), Color(red: 0.57, green: 0.3, blue: 0.26)]
        let hash = title.utf8.reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1) }
        return colors[Int(hash % UInt64(colors.count))]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if collection {
                    RoundedRectangle(cornerRadius: 5).fill(coverColor.opacity(0.4)).offset(x: 7, y: -5)
                    RoundedRectangle(cornerRadius: 5).fill(coverColor.opacity(0.7)).offset(x: 4, y: -2)
                }
                ZStack(alignment: .leading) {
                    LinearGradient(colors: [coverColor, coverColor.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped().blur(radius: 16)
                        Image(uiImage: image).resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: collection ? "books.vertical" : "headphones").font(.title3).opacity(0.7)
                            Spacer(minLength: 6)
                            Text(title).font(.system(.title3, design: .serif, weight: .semibold)).lineLimit(6).minimumScaleFactor(0.7)
                            Rectangle().frame(width: 28, height: 1).opacity(0.5)
                            Text(collection ? L10n.booksCollection : L10n.booksAudiobook).font(.system(size: 8, weight: .semibold)).tracking(1.5).textCase(.uppercase).opacity(0.7)
                        }.foregroundStyle(.white).padding(.leading, 20).padding(.trailing, 14).padding(.vertical, 20)
                    }
                    LinearGradient(colors: [.black.opacity(0.24), .white.opacity(0.15), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.22), radius: 7, x: 3, y: 6)
            }
        }.aspectRatio(0.68, contentMode: .fit).accessibilityHidden(true)
    }
}

struct BooksShelfCard: View {
    @EnvironmentObject private var theme: Theme
    let title: String
    let subtitle: String
    let collection: Bool
    var downloaded = false
    let artwork: () async -> UIImage?
    let action: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                BooksCoverView(title: title, collection: collection, image: image)
                    .overlay(alignment: .bottomTrailing) {
                        if downloaded {
                            Image(systemName: "checkmark.circle.fill").font(.title3).symbolRenderingMode(.palette)
                                .foregroundStyle(Color.white, AppTheme.color(for: .primaryInteractive01, theme: theme))
                                .padding(9)
                        }
                    }
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(3).multilineTextAlignment(.leading)
                    .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                HStack(spacing: 5) {
                    Image(systemName: collection ? "square.stack" : downloaded ? "checkmark.circle" : "arrow.down.circle")
                    Text(subtitle)
                }.font(.caption).foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
            }
            .frame(maxWidth: .infinity, alignment: .topLeading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title).accessibilityValue(subtitle)
        .accessibilityHint(collection ? L10n.booksOpenCollectionHint : downloaded ? L10n.booksQueueHint : L10n.booksDownloadHint)
        .task(id: title) { image = await artwork() }
    }
}

struct BooksReadyCard: View {
    @EnvironmentObject private var theme: Theme
    let book: PersonalBook
    let artwork: () async -> UIImage?
    let action: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                BooksCoverView(title: book.title, image: image).frame(width: 48)
                VStack(alignment: .leading, spacing: 6) {
                    Text(BooksArtwork.title(book.fileName)).font(.system(.subheadline, design: .serif, weight: .semibold)).lineLimit(2)
                        .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                    Label(L10n.booksOfflineReady, systemImage: "checkmark.circle.fill").font(.caption)
                        .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                    if book.duration > 0, book.playedUpTo > 0 {
                        ProgressView(value: min(1, book.playedUpTo / book.duration))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "text.badge.plus").font(.title2)
                    .foregroundStyle(AppTheme.color(for: .primaryInteractive01, theme: theme))
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.color(for: .primaryUi02, theme: theme), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(AppTheme.color(for: .primaryText02, theme: theme).opacity(0.12), lineWidth: 0.5))
        }.buttonStyle(.plain).accessibilityHint(L10n.booksQueueHint)
            .task(id: book.id) { image = await artwork() }
    }
}
