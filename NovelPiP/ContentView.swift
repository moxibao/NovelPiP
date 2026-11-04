import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct ContentView: View {
    @StateObject private var model = ReaderModel()
    @State private var showingImporter = false
    @State private var showingTOC = false
    @State private var showingLibrary = false
    @State private var pip = PiPRenderer()
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("NovelPiP.pipEnabled") private var pipEnabled = false

    private let importTypes: [UTType] = [.plainText, .pdf, .epub]

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    if model.selectedBook != nil {
                        reader
                    } else {
                        emptyState
                    }
                    if !model.books.isEmpty { bookshelf }
                }
                .background(Color.white)

                if model.isImporting {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在导入…").font(.system(size: 13))
                    }
                    .padding(24)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .navigationTitle("NovelPiP")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 14) {
                        Button { showingLibrary = true } label: {
                            Image(systemName: "books.vertical")
                        }
                        Button { showingTOC = true } label: {
                            Image(systemName: "list.bullet")
                        }
                        .disabled(model.selectedBook?.chapters.isEmpty ?? true)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingImporter = true } label: {
                        Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                    }
                }
            }
            .sheet(isPresented: $showingImporter) {
                DocumentPicker(contentTypes: importTypes) { url in
                    model.importFile(url: url)
                }
            }
            .sheet(isPresented: $showingTOC) {
                TOCView(model: model)
            }
            .sheet(isPresented: $showingLibrary) {
                LibraryView(model: model)
            }
            .alert("导入失败",
                   isPresented: Binding(
                    get: { model.importError != nil },
                    set: { if !$0 { model.importError = nil } }
                   ),
                   actions: { Button("好", role: .cancel) {} },
                   message: { Text(model.importError ?? "") })
        }
        .navigationViewStyle(.stack)
        .onAppear {
            if pipEnabled {
                pip.prepare(text: model.currentPage) { isForward in
                    DispatchQueue.main.async {
                        if isForward { model.nextPage() } else { model.previousPage() }
                        pip.update(text: model.currentPage)
                    }
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            handleScenePhase(phase)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            handleWillResignActive()
        }
        .onChange(of: model.pageIndex) { _ in
            if pipEnabled {
                pip.update(text: model.currentPage)
            }
        }
        .onChange(of: pipEnabled) { enabled in
            if enabled {
                pip.prepare(text: model.currentPage) { isForward in
                    DispatchQueue.main.async {
                        if isForward { model.nextPage() } else { model.previousPage() }
                        pip.update(text: model.currentPage)
                    }
                }
                pip.requestStart()
            } else {
                pip.stop()
            }
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if pipEnabled {
                pip.stop()
                pip.prepare(text: model.currentPage) { isForward in
                    DispatchQueue.main.async {
                        if isForward { model.nextPage() } else { model.previousPage() }
                        pip.update(text: model.currentPage)
                    }
                }
            }
        case .background:
            if pipEnabled {
                pip.update(text: model.currentPage)
                pip.requestStart()
            }
        default:
            break
        }
    }

    private func handleWillResignActive() {
        guard pipEnabled else { return }
        pip.update(text: model.currentPage)
        pip.requestStart()
    }

    private var reader: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedBook?.title ?? "正在阅读")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    if let ch = model.currentChapterTitle {
                        Text(ch).font(.system(size: 11)).foregroundColor(.gray)
                    }
                }
                Spacer()
                Text("\(model.pages.isEmpty ? 0 : model.pageIndex + 1) / \(model.pages.count)")
                    .font(.system(size: 12, design: .rounded).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 22).padding(.top, 14)

            ScrollView {
                Text(model.currentPage)
                    .font(.system(size: 18))
                    .lineSpacing(9)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 25)
                    .padding(.top, 28)
            }

            HStack(spacing: 30) {
                Button { model.previousPage() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18))
                }
                Text("第 \(model.pages.isEmpty ? 0 : model.pageIndex + 1) 页")
                    .font(.system(size: 13)).foregroundColor(.secondary)
                Button { model.nextPage() } label: {
                    Image(systemName: "chevron.right").font(.system(size: 18))
                }
            }
            .padding(.vertical, 16)

            Toggle(isOn: $pipEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("画中画阅读").font(.system(size: 15, weight: .medium))
                    Text("打开后划出 App，自动以画中画显示当前页")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed").font(.system(size: 42, weight: .ultraLight))
                .foregroundColor(.gray)
            Text("把小说装进口袋").font(.system(size: 20, weight: .medium))
            Text("支持 TXT / EPUB / PDF，导入后进入画中画阅读")
                .font(.system(size: 13)).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("导入小说") { showingImporter = true }
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 22).padding(.vertical, 11)
                .background(Color.black).foregroundColor(.white)
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bookshelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("书架").font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary).padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.books) { book in
                        Button { model.select(book) } label: {
                            Text(book.title)
                                .font(.system(size: 12))
                                .foregroundColor(book.id == model.selectedBookID ? .white : .black)
                                .padding(.horizontal, 13).padding(.vertical, 9)
                                .background(book.id == model.selectedBookID ? Color.black : Color(white: 0.94))
                                .clipShape(Capsule())
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                model.delete(book)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 12)
            }
        }
    }
}

struct TOCView: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(model.selectedBook?.chapters ?? []) { ch in
                    Button {
                        model.goToChapter(ch)
                        dismiss()
                    } label: {
                        HStack {
                            Text(ch.title).foregroundColor(.primary)
                            Spacer()
                            if ch.startPage == currentChapterStart {
                                Image(systemName: "checkmark").foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("目录")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var currentChapterStart: Int {
        guard let chapters = model.selectedBook?.chapters else { return -1 }
        var start = -1
        for c in chapters where c.startPage <= model.pageIndex { start = c.startPage }
        return start
    }
}

struct LibraryView: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(model.books) { book in
                    Button {
                        model.select(book)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title).foregroundColor(.primary)
                            Text("进度：第 \(book.pageIndex + 1) 页 · \(book.sourceFormat.uppercased())")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            model.delete(book)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("书库")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
