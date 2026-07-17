import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: SnapCalModel
    @State private var isImporterPresented = false

    var body: some View {
        ZStack {
            WashiCanvas()

            Group {
                switch model.phase {
                case .ready:
                    GeometryReader { proxy in
                        let historyWidth = min(
                            max(proxy.size.width * 0.25, 288),
                            360
                        )

                        HStack(spacing: 0) {
                            ImportView(
                                extractionMode: Binding(
                                    get: { model.extractionMode },
                                    set: { model.extractionMode = $0 }
                                ),
                                canImport: model.canImportSelectedMode,
                                accountMessage: model.accuracyAccountMessage,
                                accountActionTitle: model.accuracyAccountActionTitle,
                                onAccountAction: {
                                    Task { await model.performAccuracyAccountAction() }
                                },
                                onChooseScreenshot: { isImporterPresented = true },
                                onPasteScreenshot: {
                                    Task { await model.importClipboardImage() }
                                }
                            )
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity
                            )
                            .accessibilityIdentifier("importWorkspace")

                            Rectangle()
                                .fill(SnapCalPalette.line)
                                .frame(width: 1)
                                .accessibilityHidden(true)

                            RecentDraftsView(
                                drafts: model.recentDrafts,
                                issue: model.draftHistoryIssue,
                                onOpen: { id in
                                    Task { await model.openRecentDraft(id: id) }
                                },
                                onDelete: { id in
                                    Task { await model.deleteRecentDraft(id: id) }
                                }
                            )
                            .frame(width: historyWidth)
                            .frame(
                                maxHeight: .infinity,
                                alignment: .topLeading
                            )
                        }
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height,
                            alignment: .topLeading
                        )
                    }
                case .processing(let fileName):
                    ProcessingView(
                        fileName: fileName,
                        mode: model.extractionMode,
                        stage: model.processingStage
                    )
                case .review:
                    ReviewView(model: model)
                case .failed(let issue):
                    ImportErrorView(
                        issue: issue,
                        onRetry: { isImporterPresented = true },
                        onCancel: model.startOver
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: 760,
            maxWidth: .infinity,
            minHeight: 560,
            maxHeight: .infinity
        )
        .foregroundStyle(SnapCalPalette.ink)
        .tint(SnapCalPalette.vermilion)
        .task {
            await model.loadCalendarConnectionStatus()
            await model.loadAccountState()
            await model.loadRecentDrafts()
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.png, .jpeg, .heic],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    model.presentFailure(ImportIssue(
                        title: "No image selected",
                        message: "Choose one PNG, JPEG, or HEIC screenshot."
                    ))
                    return
                }
                Task {
                    await model.importScreenshot(from: url)
                }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    model.presentFailure(ImportIssue(error: error))
                }
            }
        }
    }
}

#Preview("Import") {
    ContentView(model: SnapCalModel.live())
        .frame(width: 920, height: 680)
}
