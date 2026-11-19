import LianAiCore
import SwiftUI
import UniformTypeIdentifiers

struct KnowledgeScreen: View {
  @EnvironmentObject private var model: AppModel
  @State private var state: KnowledgeState?
  @State private var query = ""
  @State private var failure = ""
  private enum Mode: Equatable { case list, read, edit }
  @State private var mode = Mode.list
  @State private var document: KnowledgeDocument?
  @State private var title = ""
  @State private var bodyText = ""
  @State private var enabled = true
  @State private var initialTitle = ""
  @State private var initialBody = ""
  @State private var initialEnabled = true
  @State private var imported = false
  @State private var importing = false
  @State private var deleting: KnowledgeDocument?
  @State private var discard = false
  @State private var afterDiscard: (() -> Void)?
  private let library = KnowledgeLibrary.shared
  private var dirty: Bool { imported || title != initialTitle || bodyText != initialBody || enabled != initialEnabled }
  var body: some View {
    VStack(spacing: 0) {
      header
      if mode == .list { list }
      else if mode == .read, let document { KnowledgeReader(document: document).padding(.top, 12) }
      else { editor.padding(.top, 12) }
    }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
      .onAppear {
        reload()
        model.knowledgeLeave = { after in requestLeave(after) }
        model.knowledgeDetail = mode != .list
      }
      .onDisappear { model.knowledgeDetail = false; model.knowledgeLeave = nil }
      .onChange(of: mode) { _, mode in model.knowledgeDetail = mode != .list }
      .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text, .data], allowsMultipleSelection: false) { result in
        switch result {
        case .failure(let error): model.notice(error.localizedDescription)
        case .success(let urls):
          guard let url = urls.first else { return }
          Task {
            do {
              let value = try await Task.detached { try KnowledgeImport.read(url) }.value
              edit(nil, importedTitle: value.title, importedBody: value.body)
            } catch { model.notice(error.localizedDescription) }
          }
        }
      }
      .alert("放弃未保存的修改？", isPresented: $discard) {
        Button("继续编辑", role: .cancel) { afterDiscard = nil }
        Button("放弃", role: .destructive) {
          let after = afterDiscard; afterDiscard = nil; showList(); after?()
        }
      }
      .alert("删除文档？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
        Button("取消", role: .cancel) { deleting = nil }
        Button("删除", role: .destructive) {
          if let document = deleting { perform { try library.remove(document.id) } }
          deleting = nil
        }
      } message: { Text("将永久删除「\(deleting?.title ?? "")」，此操作无法撤销。") }
  }
  private var header: some View {
    HStack(spacing: 0) {
      if mode != .list {
        Button { requestLeave({}) } label: { Icon(name: "chevron_left").frame(width: 52, height: 48).frame(width: 70, alignment: .leading) }
          .accessibilityLabel("返回文档列表").accessibilityIdentifier("knowledgeBack")
      } else { Color.clear.frame(width: 70, height: 48) }
      Spacer(minLength: 0)
      Text(mode == .list ? "恋爱知识库" : mode == .read ? "查看" : document == nil ? "新建文档" : "编辑文档")
        .font(.system(size: 14, weight: .bold)).lineLimit(1)
      Spacer(minLength: 0)
      Group {
        if mode == .list {
          Menu {
            Button("新建文档") { edit(nil) }.accessibilityIdentifier("knowledgeCreate")
            Button("导入本机文档") { importing = true }.accessibilityIdentifier("knowledgeImport")
          } label: { Text("添加").frame(width: 70, height: 48) }.accessibilityIdentifier("knowledgeAdd")
        } else if mode == .edit {
          Button("保存", action: save).frame(width: 70, height: 48).accessibilityIdentifier("knowledgeSave")
        } else if document?.isSystem == false {
          Button("编辑") { if let document { edit(document) } }.frame(width: 70, height: 48).accessibilityIdentifier("knowledgeEdit")
        } else { Color.clear.frame(width: 70, height: 48) }
      }.font(.system(size: 14)).foregroundStyle(LA.accent)
    }.foregroundStyle(LA.ink)
  }
  private var list: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").foregroundStyle(LA.muted).accessibilityHidden(true)
        TextField("搜索文档", text: $query).font(.system(size: 14)).autocorrectionDisabled()
          .accessibilityIdentifier("knowledgeSearch")
      }.padding(.horizontal, 16).frame(height: 48).background(LA.panel, in: RoundedRectangle(cornerRadius: 22)).padding(.top, 12)
      let documents = state?.matching(query) ?? []
      Text("全部文档 · \(documents.count) 份").font(.system(size: 12)).foregroundStyle(LA.muted)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4).padding(.top, 16).padding(.bottom, 12)
        .accessibilityIdentifier("knowledgeCount")
      ScrollView {
        LazyVStack(spacing: 0) {
          if !failure.isEmpty {
            Text(failure).padding(24)
            Button("重试", action: reload).padding()
          } else if documents.isEmpty {
            Text(query.isEmpty ? "暂无文档\n点击右上角添加文档或导入本机文件" : "没有匹配的文档")
              .font(.system(size: 14)).foregroundStyle(LA.muted).multilineTextAlignment(.center).padding(30)
          } else {
            ForEach(documents) { document in
              documentRow(document)
              if document.id != documents.last?.id { Rectangle().fill(LA.key).frame(height: 1) }
            }
          }
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity).background(LA.panel, in: RoundedRectangle(cornerRadius: 24)).clipShape(RoundedRectangle(cornerRadius: 24))
    }
  }
  private func documentRow(_ document: KnowledgeDocument) -> some View {
    HStack(spacing: 0) {
      Button {
        self.document = document; mode = .read
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "doc.text").font(.system(size: 29, weight: .light)).foregroundStyle(LA.accent).frame(width: 34, height: 42).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 6) {
            Text(document.title).font(.system(size: 16, weight: .bold)).lineLimit(2).foregroundStyle(LA.ink)
            Text((document.isSystem ? "系统知识库 · " : "") + (document.id == state?.defaultDocumentID ? "默认 · " : "") + "\(document.body.utf16.count) 字 · \(document.enabled ? "已启用" : "已停用")")
              .font(.system(size: 12)).foregroundStyle(LA.muted)
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityIdentifier("knowledgeDocument.\(document.id)")
      Menu {
        if !document.isSystem { Button("编辑文档") { edit(document) } }
        Button(document.enabled ? "停用" : "启用") { perform { try library.setEnabled(document.id, !document.enabled) } }
        Button { perform { try library.setDefault(document.id); model.notice(document.enabled ? "已设为默认知识库" : "已设为默认知识库并启用") } } label: {
          if state?.defaultDocumentID == document.id { Label("设为默认", systemImage: "checkmark") } else { Text("设为默认") }
        }
        if !document.isSystem { Button("删除文档", role: .destructive) { deleting = document } }
      } label: { Text("⋯").font(.system(size: 22)).foregroundStyle(LA.accent).frame(width: 48, height: 48) }
        .accessibilityLabel(document.title + "的更多操作").accessibilityIdentifier("knowledgeMore.\(document.id)")
    }.padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 12).frame(minHeight: 88)
  }
  private var editor: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("文档标题", text: $title).font(.system(size: 17)).padding(.vertical, 8)
        .accessibilityIdentifier("knowledgeTitle")
      ZStack(alignment: .topLeading) {
        if bodyText.isEmpty { Text("支持 Markdown：标题、加粗、列表、引用、表格").font(.system(size: 14)).foregroundStyle(LA.muted).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false).accessibilityHidden(true) }
        TextEditor(text: $bodyText).font(.system(size: 14)).scrollContentBackground(.hidden)
          .accessibilityLabel("文档完整正文").accessibilityIdentifier("knowledgeBody")
      }.frame(maxHeight: .infinity)
      Button { enabled.toggle() } label: {
        HStack(spacing: 8) {
          Image(systemName: enabled ? "checkmark.square.fill" : "square").font(.system(size: 22)).foregroundStyle(enabled ? LA.accent : LA.muted)
          Text("启用此文档").font(.system(size: 14)).foregroundStyle(LA.muted)
        }.padding(.vertical, 8)
      }.buttonStyle(.plain).accessibilityIdentifier("knowledgeEnabled").accessibilityValue(enabled ? "1" : "0")
    }.padding(.horizontal, 16).padding(.vertical, 12).background(LA.panel, in: RoundedRectangle(cornerRadius: 24))
  }
  private func reload() {
    do { state = try library.read(); failure = "" }
    catch { failure = "文档读取或保存失败，原资料已保留，请重试"; model.notice(failure) }
  }
  private func perform(_ action: () throws -> Void) {
    do { try action(); reload() } catch { model.notice(error.localizedDescription) }
  }
  private func edit(_ document: KnowledgeDocument?, importedTitle: String = "", importedBody: String = "") {
    self.document = document
    title = document?.title ?? importedTitle; bodyText = document?.body ?? importedBody; enabled = document?.enabled ?? true
    initialTitle = title; initialBody = bodyText; initialEnabled = enabled; imported = !importedBody.isEmpty
    mode = .edit
  }
  private func showList() { mode = .list; document = nil; reload() }
  private func requestLeave(_ after: @escaping () -> Void) {
    if mode == .edit && dirty { afterDiscard = after; discard = true }
    else { showList(); after() }
  }
  private func save() {
    do {
      try library.save(KnowledgeDocument(id: document?.id ?? UUID().uuidString, title: title, body: bodyText, enabled: enabled))
      showList(); model.notice("文档已保存")
    } catch { model.notice(error.localizedDescription) }
  }
}

private struct KnowledgeReader: View {
  let document: KnowledgeDocument
  @State private var blocks: [KnowledgeMarkdown.Block] = []
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 14) {
        ForEach(blocks) { block in
          switch block.kind {
          case .heading(let level):
            inline(block.text).font(.system(size: [25, 21, 18, 16.5, 15, 15][min(5,level-1)], weight: .bold)).padding(.top, 4)
          case .paragraph: inline(block.text).font(.system(size: 15)).lineSpacing(5)
          case .quote: HStack(alignment: .top, spacing: 12) { Rectangle().fill(LA.accent).frame(width: 3); inline(block.text).font(.system(size: 15)).lineSpacing(5) }.fixedSize(horizontal: false, vertical: true)
          case .code: Text(block.text).font(.system(size: 13, design: .monospaced)).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(LA.key.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
          case .divider: Rectangle().fill(LA.key).frame(height: 1)
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 28).textSelection(.enabled)
    }.background(LA.panel, in: RoundedRectangle(cornerRadius: 24)).clipShape(RoundedRectangle(cornerRadius: 24))
      .accessibilityIdentifier("knowledgeReader")
      .task(id: document.id + String(document.updatedAt.timeIntervalSince1970)) {
        let source = document.body
        let parsed = await Task.detached { KnowledgeMarkdown.parse(source) }.value
        if !Task.isCancelled { blocks = parsed }
      }
  }
  private func inline(_ source: String) -> some View {
    Text((try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)).foregroundStyle(LA.ink).tint(LA.accent)
  }
}
