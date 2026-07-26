import AppKit
import SottoCore
import SwiftUI

struct DictationHistoryView: View {
    @EnvironmentObject private var store: DictationHistoryStore
    @State private var query = ""
    @State private var confirmsClearAll = false

    private var matchingEntries: [DictationHistoryEntry] {
        store.search(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let errorMessage = store.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.10))
                    .clipShape(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
            }

            TextField("搜索听写内容", text: $query)
                .textFieldStyle(.roundedBorder)

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
        .padding(28)
        .navigationTitle("历史")
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

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("历史")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("仅保存在本机，30 天后自动删除。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("清空全部", role: .destructive) {
                confirmsClearAll = true
            }
            .disabled(store.entries.isEmpty)
        }
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
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    store.delete(id: entry.id)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func emptyState(
        symbol: String,
        title: String,
        detail: String
    ) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
