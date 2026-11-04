import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct ContentView: View {
    @StateObject private var model = ReaderModel()
    @State private var showingImporter = false
    @State private var pip = PiPRenderer()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if model.selectedBook != nil {
                    reader
                } else {
                    emptyState
                }
                if !model.books.isEmpty { bookshelf }
            }
            .background(Color.white)
            .navigationTitle("NovelPiP")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingImporter = true } label: {
                        Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                    }
                }
            }
            .fileImporter(
    isPresented: $showingImporter,
    allowedContentTypes: [
        .plainText,
        .text,
        UTType(filenameExtension: "txt") ?? .plainText
    ],
    allowsMultipleSelection: false
) { result in
    switch result {
    case .success(let urls):
        guard let url = urls.first else {
            return
        }

        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)

            guard !data.isEmpty else {
                print("导入失败：文件内容为空")
                return
            }

            model.importText(
                data: data,
                filename: url.lastPathComponent
            )

        } catch {
            print("导入文件失败：\(error.localizedDescription)")
        }

    case .failure(let error):
        print("文件选择失败：\(error.localizedDescription)")
    }
}
        }
        .navigationViewStyle(.stack)
    }

    private var reader: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.selectedBook?.title ?? "正在阅读")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
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

            Button {
                pip.start(text: model.currentPage) { isForward in
                    DispatchQueue.main.async {
                        if isForward { model.nextPage() } else { model.previousPage() }
                        pip.update(text: model.currentPage)
                    }
                }
            } label: {
                Label("进入画中画阅读", systemImage: "pip")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.black).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 22).padding(.bottom, 18)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed").font(.system(size: 42, weight: .ultraLight))
                .foregroundColor(.gray)
            Text("把小说装进口袋").font(.system(size: 20, weight: .medium))
            Text("导入 TXT 文件，开启画中画阅读")
                .font(.system(size: 13)).foregroundColor(.secondary)
            Button("导入 TXT 小说") { showingImporter = true }
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
                    }
                }.padding(.horizontal, 20).padding(.bottom, 12)
            }
        }
    }
}
