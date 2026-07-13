import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = SnapCalModel.live()
    @State private var isImporterPresented = false

    var body: some View {
        Group {
            switch model.phase {
            case .ready:
                ImportView(
                    extractionMode: Binding(
                        get: { model.extractionMode },
                        set: { model.extractionMode = $0 }
                    )
                ) {
                    isImporterPresented = true
                }
            case .processing(let fileName):
                ProcessingView(fileName: fileName, mode: model.extractionMode)
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
        .frame(minWidth: 760, minHeight: 560)
        .task {
            await model.loadCalendarConnectionStatus()
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
    ContentView()
        .frame(width: 920, height: 680)
}
