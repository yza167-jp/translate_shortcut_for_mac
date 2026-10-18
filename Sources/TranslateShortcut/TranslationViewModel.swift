import AppKit
import TranslationCore

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var mode: TranslationMode = .translate
    @Published var input = ""
    @Published private(set) var output = ""
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var notice: String?
    @Published var sourceName: String?
    @Published private(set) var wasCancelled = false
    @Published var copied = false
    let settings: SettingsStore
    private let client = TranslationClient()
    private var task: Task<Void, Never>?
    private var requestID = UUID()

    init(settings: SettingsStore) { self.settings = settings }

    func prepare(mode: TranslationMode, selection: SelectionResult, source: String?) {
        cancel()
        self.mode = mode
        input = selection.text
        notice = selection.notice
        sourceName = source
        output = ""
        error = nil
        wasCancelled = false
        copied = false
    }

    func submit() {
        cancel()
        let configuration = settings.configuration
        let key = settings.apiKey
        let text = input
        let selectedMode = mode
        output = ""
        error = nil
        copied = false
        wasCancelled = false
        do { _ = try client.makeRequest(configuration: configuration, apiKey: key, text: text, mode: selectedMode) }
        catch { self.error = error.localizedDescription; return }
        let id = UUID()
        requestID = id
        isLoading = true
        task = Task { [weak self, client] in
            do {
                let result = try await client.translate(configuration: configuration, apiKey: key, text: text,
                                                        mode: selectedMode) { [weak self] partial in
                    await self?.update(partial, for: id)
                }
                guard let self, requestID == id, !Task.isCancelled else { return }
                output = result
                isLoading = false
                task = nil
            } catch {
                guard let self, requestID == id, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                isLoading = false
                task = nil
            }
        }
    }

    private func update(_ partial: String, for id: UUID) {
        guard requestID == id else { return }
        output = partial
    }

    func cancel() {
        requestID = UUID()
        task?.cancel()
        task = nil
        if isLoading { wasCancelled = true }
        isLoading = false
    }

    func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        copied = true
    }
}
