import PocketCastsUtils
import UIKit
import UniformTypeIdentifiers

/// Imports a user-selected copy, using the app's existing subscription importer.
@MainActor
final class PodcastOpmlFileImporter: NSObject, UIDocumentPickerDelegate {
    private weak var presenter: UIViewController?
    private var progress: ShiftyLoadingAlert?

    init(presenter: UIViewController) {
        self.presenter = presenter
    }

    func present() {
        let types: [UTType] = [.xml, .plainText, UTType(filenameExtension: "opml"), UTType("public.opml"), UTType("unofficial.opml")].compactMap { $0 }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presenter?.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let presenter else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("opml")
            try FileManager.default.copyItem(at: url, to: copy)
            let progress = ShiftyLoadingAlert(title: L10n.opmlImporting)
            self.progress = progress
            progress.showAlert(presenter, hasProgress: false) {
                PodcastManager.shared.importPodcastsFromOpml(copy, progressWindow: progress)
            }
        } catch {
            SJUIUtils.showAlert(title: L10n.opmlImportFailedTitle, message: L10n.opmlImportFailedMessage, from: presenter)
        }
    }
}
