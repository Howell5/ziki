import AppKit
import ZikiCore
import SwiftUI

struct DictationHistoryView: View {
    @EnvironmentObject private var store: DictationHistoryStore
    @State private var query = ""
    @State private var confirmsClearAll = false
    @State private var copiedEntryID: UUID?

    private var matchingEntries: [DictationHistoryEntry] {
        store.search(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let errorMessage = store.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(ZikiTheme.ink)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ZikiTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(ZikiTheme.line, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            searchRow

            Group {
                if store.entries.isEmpty {
                    emptyState(
                        symbol: "clock",
                        title: "还没有听写记录",
                        detail: "完成一次有效听写后，最终文本会出现在这里。"
                    )
                } else if matchingEntries.isEmpty {
                    emptyState(
                        symbol: "magnifyingglass",
                        title: "没有匹配结果",
                        detail: "换一个关键词再试试。"
                    )
                } else {
                    historyList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .background(ZikiTheme.paper.ignoresSafeArea())
        .confirmationDialog(
            "清空全部听写历史？",
            isPresented: $confirmsClearAll,
            titleVisibility: .visible
        ) {
            Button("清空全部", role: .destructive) {
                store.clearAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会立即删除本机保存的全部最终文本，且无法恢复。")
        }
        .task {
            store.purgeExpired()
        }
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ZikiTheme.ink.opacity(0.58))

            TextField("搜索听写内容", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(ZikiTheme.ink)
                .accessibilityIdentifier("dictation-history-search")

            Text(resultCountLabel)
                .font(.subheadline)
                .foregroundStyle(ZikiTheme.ink.opacity(0.58))
                .fixedSize()

            Button("清空全部", role: .destructive) {
                confirmsClearAll = true
            }
            .buttonStyle(.borderless)
            .disabled(store.entries.isEmpty)
            .accessibilityIdentifier("dictation-history-clear-all")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .zikiCard()
    }

    private var resultCountLabel: String {
        let total = store.entries.count
        let matching = matchingEntries.count
        return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "共 \(total) 条"
            : "\(matching) / \(total) 条"
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(matchingEntries) { entry in
                    historyCard(entry)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func historyCard(_ entry: DictationHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(
                    entry.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                Text("·")
                Text(
                    DictationHistoryPolicy.providerTitle(
                        for: entry.providerID
                    )
                )
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(entry.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button {
                    copy(entry.text)
                    copiedEntryID = entry.id
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        if copiedEntryID == entry.id {
                            copiedEntryID = nil
                        }
                    }
                } label: {
                    Label(
                        copiedEntryID == entry.id ? "已复制" : "复制",
                        systemImage: copiedEntryID == entry.id
                            ? "checkmark"
                            : "doc.on.doc"
                    )
                }
                Button(role: .destructive) {
                    store.delete(id: entry.id)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .foregroundStyle(ZikiTheme.ink)
        .zikiCard()
    }

    private func emptyState(
        symbol: String,
        title: String,
        detail: String
    ) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(ZikiTheme.ink.opacity(0.35))
            Text(title)
                .font(.headline)
                .foregroundStyle(ZikiTheme.ink)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(ZikiTheme.ink.opacity(0.58))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
