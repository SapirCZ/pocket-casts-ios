import PocketCastsUtils
import SwiftUI
import UIKit

final class BooksViewController: PCHostingController<BooksLibraryView> {
    init() {
        super.init(rootView: BooksLibraryView())
        title = L10n.booksTitle
    }

    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct BooksLibraryView: View {
    @EnvironmentObject private var theme: Theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.color(for: .primaryIcon01, theme: theme))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.booksLibraryTitle)
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                    Text(L10n.booksLibraryDescription)
                        .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                }

                Label(L10n.booksConnectionPending, systemImage: "link")
                    .font(.callout)
                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.color(for: .primaryUi02, theme: theme), in: RoundedRectangle(cornerRadius: 16))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(AppTheme.color(for: .primaryUi01, theme: theme).ignoresSafeArea())
    }
}
