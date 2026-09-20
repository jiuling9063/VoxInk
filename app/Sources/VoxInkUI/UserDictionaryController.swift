import Combine
import Foundation
import VoxInkCore

@MainActor public final class UserDictionaryController: ObservableObject {
    @Published public private(set) var entries: [UserDictionaryEntry] = []
    @Published public private(set) var isReady = false
    @Published public private(set) var isUpdating = false
    @Published public private(set) var errorMessage: String?
    public private(set) var rules = UserDictionaryRules.empty
    private let storage: any UserDictionaryStorage
    private var updateWaiters: [CheckedContinuation<Void, Never>] = []
    public init(storage: any UserDictionaryStorage) { self.storage = storage }
    public func clearEditingError() { if isReady { errorMessage = nil } }

    public func waitForPendingChanges() async {
        guard isUpdating else { return }
        await withCheckedContinuation { updateWaiters.append($0) }
    }

    private func finishUpdate() {
        isUpdating = false
        let waiting = updateWaiters; updateWaiters.removeAll()
        for continuation in waiting { continuation.resume() }
    }

    public func load() async {
        guard !isUpdating else { return }
        isUpdating = true; defer { finishUpdate() }
        do {
            let loaded = try await storage.load()
            let normalized = try loaded.map { try candidate(source: $0.source, replacement: $0.replacement, id: $0.id) }
            rules = try UserDictionaryRules(entries: normalized)
            entries = normalized; isReady = true; errorMessage = nil
        } catch {
            errorMessage = (error as? UserDictionaryError)?.localizedDescription ?? "词典读取失败，请检查磁盘访问权限后重试。"
        }
    }

    public func candidate(source: String, replacement: String, id: UUID = UUID()) throws -> UserDictionaryEntry {
        guard source.utf8.count <= 512, replacement.utf8.count <= 512 else { throw UserDictionaryError.termTooLong }
        // Match the same canonical prose that reaches the dictionary during transcription.
        let cleanSource = DeterministicTextProcessor.shared.process(source).text
        let cleanTarget = DeterministicTextProcessor.shared.process(replacement).text
        return try UserDictionaryEntry(id: id, source: cleanSource, replacement: cleanTarget)
    }

    @discardableResult public func save(source: String, replacement: String, id: UUID? = nil) async -> Bool {
        guard isReady, !isUpdating else { return false }
        do {
            let entry = try candidate(source: source, replacement: replacement, id: id ?? UUID())
            var changed = entries
            if let id {
                guard let index = changed.firstIndex(where: { $0.id == id }) else { return false }
                changed[index] = entry
            } else { changed.append(entry) }
            return await persist(changed)
        } catch {
            errorMessage = (error as? UserDictionaryError)?.localizedDescription ?? "词条无效，请检查内容。"
            return false
        }
    }

    public func remove(_ id: UUID) async {
        guard isReady, !isUpdating else { return }
        _ = await persist(entries.filter { $0.id != id })
    }

    public struct ImportPreview: Identifiable {
        public let id = UUID()
        let original: [UserDictionaryEntry]
        let additions: [UserDictionaryEntry]
        let notices: [String]
        let duplicates: Int
        let conflicts: Int
        let invalid: Int
        let blockingError: String?
    }

    public func previewImport(_ data: Data) throws -> ImportPreview {
        let rows = try UserDictionaryCSV.decode(data)
        var known = Dictionary(uniqueKeysWithValues: entries.map { ($0.source, $0.replacement) })
        var additions: [UserDictionaryEntry] = [], notices: [String] = []
        var duplicates = 0, conflicts = 0, invalid = 0
        for row in rows {
            do {
                let entry = try candidate(source: row.source, replacement: row.replacement)
                if let target = known[entry.source] {
                    if target == entry.replacement { duplicates += 1 }
                    else {
                        conflicts += 1
                        notices.append("第 \(row.number) 行：\(entry.source) 已有写法“\(target)”，跳过冲突项。")
                    }
                } else {
                    known[entry.source] = entry.replacement; additions.append(entry)
                }
            } catch {
                invalid += 1
                notices.append("第 \(row.number) 行：\(error.localizedDescription)")
            }
        }
        var blockingError: String?
        do { _ = try UserDictionaryRules(entries: entries + additions) }
        catch { blockingError = error.localizedDescription }
        return ImportPreview(original: entries, additions: additions, notices: notices,
                             duplicates: duplicates, conflicts: conflicts, invalid: invalid, blockingError: blockingError)
    }

    @discardableResult public func importConfirmed(_ preview: ImportPreview) async -> Bool {
        guard isReady, !isUpdating, preview.blockingError == nil, !preview.additions.isEmpty else { return false }
        guard entries == preview.original else {
            errorMessage = "词库已变化，请重新选择文件并预览。"; return false
        }
        return await persist(entries + preview.additions)
    }

    private func persist(_ changed: [UserDictionaryEntry]) async -> Bool {
        isUpdating = true; defer { finishUpdate() }
        do {
            let updatedRules = try UserDictionaryRules(entries: changed)
            try await storage.save(changed)
            entries = changed; rules = updatedRules; errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? UserDictionaryError)?.localizedDescription ?? "词典保存失败，上次有效配置仍然生效。请检查磁盘空间与访问权限。"
            return false
        }
    }
}
