import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// Gemini 기반 AI 도구를 모아 입력 선택, 처리 상태, 미리보기 저장 흐름을 관리합니다.
struct UtilitiesView: View {
    let saveOCRResult: (HandwritingOCRResult) -> Void
    let saveMeetingSummaryResult: (MeetingSummaryResult) -> Void
    let saveReceiptScanResult: (ReceiptScanResult) -> Void
    let saveBusinessCardScanResult: (BusinessCardScanResult) -> Void
    let saveDocumentScanResult: (DocumentScanResult) -> Void
    let saveFileSummaryResult: (FileSummaryResult) -> Void

    @State private var ocrPreview: HandwritingOCRResult?
    @State private var meetingPreview: MeetingSummaryResult?
    @State private var receiptPreview: ReceiptScanResult?
    @State private var businessCardPreview: BusinessCardScanResult?
    @State private var documentScanPreview: DocumentScanResult?
    @State private var fileSummaryPreview: FileSummaryResult?
    @State private var isProcessingOCR = false
    @State private var isProcessingMeeting = false
    @State private var isProcessingReceipt = false
    @State private var isProcessingBusinessCard = false
    @State private var isProcessingDocumentScan = false
    @State private var isProcessingFileSummary = false
    @State private var ocrError: String?
    @State private var meetingError: String?
    @State private var receiptError: String?
    @State private var businessCardError: String?
    @State private var documentScanError: String?
    @State private var fileSummaryError: String?
    @State private var ocrTask: Task<Void, Never>?
    @State private var meetingTask: Task<Void, Never>?
    @State private var receiptTask: Task<Void, Never>?
    @State private var businessCardTask: Task<Void, Never>?
    @State private var documentScanTask: Task<Void, Never>?
    @State private var fileSummaryTask: Task<Void, Never>?
    @State private var ocrTaskID: UUID?
    @State private var meetingTaskID: UUID?
    @State private var receiptTaskID: UUID?
    @State private var businessCardTaskID: UUID?
    @State private var documentScanTaskID: UUID?
    @State private var fileSummaryTaskID: UUID?
    @State private var ocrStage: AIProcessingStage = .preparingInput
    @State private var meetingStage: AIProcessingStage = .preparingInput
    @State private var receiptStage: AIProcessingStage = .preparingInput
    @State private var businessCardStage: AIProcessingStage = .preparingInput
    @State private var documentScanStage: AIProcessingStage = .preparingInput
    @State private var fileSummaryStage: AIProcessingStage = .preparingInput

    private let features: [UtilityFeature] = [
        UtilityFeature(
            kind: .handwritingOCR,
            section: .convertToNote,
            title: "손글씨 인식",
            listSubtitle: "손글씨를 메모 블록으로 변환",
            subtitle: "손글씨와 화이트보드를 메모 블록으로 바꿉니다.",
            description: "종이에 적은 손글씨나 화이트보드 내용을 읽어 NoteFlow 메모 블록으로 변환합니다. 결과를 확인한 뒤 새 메모로 바로 저장할 수 있습니다.",
            systemImage: "text.viewfinder",
            inputLabel: "이미지"
        ),
        UtilityFeature(
            kind: .meetingSummary,
            section: .convertToNote,
            title: "회의 요약",
            listSubtitle: "음성을 회의록과 요약으로 정리",
            subtitle: "음성을 회의록과 핵심 요약으로 정리합니다.",
            description: "녹음한 회의나 가져온 음성 파일을 읽어 제목, 핵심 요약, 회의록 본문으로 정리합니다. 결과를 확인한 뒤 새 메모로 저장할 수 있습니다.",
            systemImage: "waveform",
            inputLabel: "음성"
        ),
        UtilityFeature(
            kind: .fileSummary,
            section: .convertToNote,
            title: "파일 요약",
            listSubtitle: "PDF, TXT, DOCX를 요약 메모로 변환",
            subtitle: "PDF, TXT, DOCX를 요약 메모로 정리합니다.",
            description: "가져온 파일의 내용을 읽어 제목, 핵심 요약, 정리 본문으로 바꿉니다. 결과를 수정한 뒤 NoteFlow 메모로 저장할 수 있습니다.",
            systemImage: "doc.text.magnifyingglass",
            inputLabel: "파일"
        ),
        UtilityFeature(
            kind: .documentScan,
            section: .organizeDocument,
            title: "문서 스캔",
            listSubtitle: "종이 문서를 텍스트 메모로 변환",
            subtitle: "종이 문서를 텍스트 메모로 바꿉니다.",
            description: "계약서, 출력물, 종이 문서를 촬영해 제목과 본문, 표 구조를 갖춘 메모로 변환합니다. 결과를 확인한 뒤 새 메모로 저장할 수 있습니다.",
            systemImage: "doc.viewfinder",
            inputLabel: "이미지"
        ),
        UtilityFeature(
            kind: .receipt,
            section: .organizeDocument,
            title: "영수증 스캔",
            listSubtitle: "결제 정보를 지출 내역으로 정리",
            subtitle: "영수증에서 날짜, 금액, 가맹점을 정리합니다.",
            description: "영수증 속 결제 정보를 읽어 지출 내역으로 정리합니다. 날짜, 금액, 가맹점, 품목을 확인한 뒤 새 메모로 바로 저장할 수 있습니다.",
            systemImage: "receipt",
            inputLabel: "이미지"
        ),
        UtilityFeature(
            kind: .businessCard,
            section: .organizeDocument,
            title: "명함 스캔",
            listSubtitle: "명함 정보를 연락처 메모로 정리",
            subtitle: "명함 정보를 연락처 형태로 정리합니다.",
            description: "명함 속 이름, 회사, 직책, 전화번호, 이메일을 읽어 정돈된 메모로 바꿉니다. 연락처 앱 연동 없이 NoteFlow 메모로 저장합니다.",
            systemImage: "person.crop.rectangle",
            inputLabel: "이미지"
        )
    ]

    private var featureSections: [UtilityFeatureSection] {
        UtilityFeatureSection.allCases.filter { section in
            features.contains { $0.section == section }
        }
    }

    var body: some View {
        List {
            ForEach(featureSections) { section in
                UtilityFeatureSectionView(
                    section: section,
                    features: features.filter { $0.section == section },
                    showsProviderFooter: section == .organizeDocument,
                    isProcessing: isProcessing,
                    processImage: processImage,
                    processAudio: processAudio,
                    processFile: processFile
                )
            }

            BottomTabBarListSpacer(height: MainTabLayout.bottomContentInset + 24)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("AI 도구")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $ocrPreview) { result in
            HandwritingOCRPreviewSheet(
                result: result,
                save: { editedResult in
                    saveOCRResult(editedResult)
                    ocrPreview = nil
                },
                cancel: {
                    ocrPreview = nil
                }
            )
        }
        .fullScreenCover(isPresented: $isProcessingOCR) {
            UtilityAIProcessingView(
                message: processingMessage(for: .handwritingOCR),
                cancel: { cancelProcessing(.handwritingOCR) }
            )
        }
        .fullScreenCover(isPresented: $isProcessingMeeting) {
            UtilityAIProcessingView(
                message: processingMessage(for: .meetingSummary),
                cancel: { cancelProcessing(.meetingSummary) }
            )
        }
        .fullScreenCover(isPresented: $isProcessingReceipt) {
            UtilityAIProcessingView(
                message: processingMessage(for: .receipt),
                cancel: { cancelProcessing(.receipt) }
            )
        }
        .fullScreenCover(isPresented: $isProcessingBusinessCard) {
            UtilityAIProcessingView(
                message: processingMessage(for: .businessCard),
                cancel: { cancelProcessing(.businessCard) }
            )
        }
        .fullScreenCover(isPresented: $isProcessingDocumentScan) {
            UtilityAIProcessingView(
                message: processingMessage(for: .documentScan),
                cancel: { cancelProcessing(.documentScan) }
            )
        }
        .fullScreenCover(isPresented: $isProcessingFileSummary) {
            UtilityAIProcessingView(
                message: processingMessage(for: .fileSummary),
                cancel: { cancelProcessing(.fileSummary) }
            )
        }
        .sheet(item: $receiptPreview) { result in
            ReceiptScanPreviewSheet(
                result: result,
                save: { editedResult in
                    saveReceiptScanResult(editedResult)
                    receiptPreview = nil
                },
                cancel: {
                    receiptPreview = nil
                }
            )
        }
        .sheet(item: $businessCardPreview) { result in
            BusinessCardScanPreviewSheet(
                result: result,
                save: { editedResult in
                    saveBusinessCardScanResult(editedResult)
                    businessCardPreview = nil
                },
                cancel: {
                    businessCardPreview = nil
                }
            )
        }
        .sheet(item: $meetingPreview) { result in
            MeetingSummaryPreviewSheet(
                result: result,
                save: { editedResult in
                    saveMeetingSummaryResult(editedResult)
                    meetingPreview = nil
                },
                cancel: {
                    meetingPreview = nil
                }
            )
        }
        .sheet(item: $documentScanPreview) { result in
            DocumentScanPreviewSheet(
                result: result,
                save: { editedResult in
                    saveDocumentScanResult(editedResult)
                    documentScanPreview = nil
                },
                cancel: {
                    documentScanPreview = nil
                }
            )
        }
        .sheet(item: $fileSummaryPreview) { result in
            FileSummaryPreviewSheet(
                result: result,
                save: { editedResult in
                    saveFileSummaryResult(editedResult)
                    fileSummaryPreview = nil
                },
                cancel: {
                    fileSummaryPreview = nil
                }
            )
        }
        .alert("손글씨 변환 실패", isPresented: Binding(
            get: { ocrError != nil },
            set: { isPresented in
                if !isPresented {
                    ocrError = nil
                }
            }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(ocrError ?? "")
        }
        .alert("회의 요약 실패", isPresented: Binding(
            get: { meetingError != nil },
            set: { isPresented in
                if !isPresented {
                    meetingError = nil
                }
            }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(meetingError ?? "")
        }
        .alert("지출 스캔 실패", isPresented: Binding(
            get: { receiptError != nil },
            set: { isPresented in
                if !isPresented {
                    receiptError = nil
                }
            }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(receiptError ?? "")
        }
        .alert("연락처 스캔 실패", isPresented: Binding(
            get: { businessCardError != nil },
            set: { isPresented in
                if !isPresented {
                    businessCardError = nil
                }
            }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(businessCardError ?? "")
        }
        .alert("문서 스캔 실패", isPresented: Binding(
            get: { documentScanError != nil },
            set: { isPresented in
                if !isPresented {
                    documentScanError = nil
                }
            }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(documentScanError ?? "")
        }
        .alert("파일 요약 실패", isPresented: Binding(
            get: { fileSummaryError != nil },
            set: { isPresented in
                if !isPresented {
                    fileSummaryError = nil
                }
            }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(fileSummaryError ?? "")
        }
    }

    private func processImage(_ image: UIImage, kind: UtilityFeatureKind) {
        guard let imageData = image.normalizedJPEGData(maxDimension: 1800) else {
            setImageProcessingError(for: kind, message: "이미지를 처리하지 못했습니다.")
            return
        }

        switch kind {
        case .receipt:
            processReceiptImage(imageData)
        case .businessCard:
            processBusinessCardImage(imageData)
        case .handwritingOCR:
            processHandwritingImage(imageData)
        case .documentScan:
            processDocumentImage(imageData)
        case .meetingSummary:
            break
        case .fileSummary:
            break
        }
    }

    private func processHandwritingImage(_ imageData: Data) {
        guard !isProcessingOCR else {
            return
        }

        // 같은 기능이 중복 실행되지 않도록 처리 상태와 taskID를 함께 세팅합니다.
        isProcessingOCR = true
        ocrError = nil
        let taskID = UUID()
        ocrTaskID = taskID
        setProcessingStage(.preparingInput, for: .handwritingOCR)

        ocrTask = Task {
            do {
                // 서비스가 진행 단계를 알려주면 현재 taskID와 맞을 때만 UI에 반영합니다.
                let updateStage = stageUpdater(for: .handwritingOCR, taskID: taskID)
                let result = try await GeminiHandwritingOCRService.recognize(
                    imageData: imageData,
                    mimeType: "image/jpeg",
                    updateStage: updateStage
                )
                try Task.checkCancellation()
                await updateStage(.preparingPreview)
                await MainActor.run {
                    guard ocrTaskID == taskID else {
                        return
                    }
                    // 결과가 도착한 뒤에는 바로 저장하지 않고 미리보기 시트로 넘깁니다.
                    ocrPreview = result
                    finishProcessing(.handwritingOCR)
                }
            } catch {
                await MainActor.run {
                    guard ocrTaskID == taskID else {
                        return
                    }
                    finishProcessing(.handwritingOCR)
                    guard !isCancellationError(error) else {
                        // 사용자가 취소한 작업은 실패 alert를 띄우지 않습니다.
                        return
                    }
                    ocrError = GeminiServiceError.message(
                        for: error,
                        fallback: "손글씨를 인식하지 못했습니다. 이미지를 다시 선택해 주세요."
                    )
                }
            }
        }
    }

    private func processReceiptImage(_ imageData: Data) {
        guard !isProcessingReceipt else {
            return
        }

        isProcessingReceipt = true
        receiptError = nil
        let taskID = UUID()
        receiptTaskID = taskID
        setProcessingStage(.preparingInput, for: .receipt)

        receiptTask = Task {
            do {
                let updateStage = stageUpdater(for: .receipt, taskID: taskID)
                let result = try await GeminiReceiptScanService.scan(
                    imageData: imageData,
                    mimeType: "image/jpeg",
                    updateStage: updateStage
                )
                try Task.checkCancellation()
                await updateStage(.preparingPreview)
                await MainActor.run {
                    guard receiptTaskID == taskID else {
                        return
                    }
                    receiptPreview = result
                    finishProcessing(.receipt)
                }
            } catch {
                await MainActor.run {
                    guard receiptTaskID == taskID else {
                        return
                    }
                    finishProcessing(.receipt)
                    guard !isCancellationError(error) else {
                        return
                    }
                    receiptError = GeminiServiceError.message(
                        for: error,
                        fallback: "영수증을 분석하지 못했습니다. 이미지를 다시 선택해 주세요."
                    )
                }
            }
        }
    }

    private func processBusinessCardImage(_ imageData: Data) {
        guard !isProcessingBusinessCard else {
            return
        }

        isProcessingBusinessCard = true
        businessCardError = nil
        let taskID = UUID()
        businessCardTaskID = taskID
        setProcessingStage(.preparingInput, for: .businessCard)

        businessCardTask = Task {
            do {
                let updateStage = stageUpdater(for: .businessCard, taskID: taskID)
                let result = try await GeminiBusinessCardScanService.scan(
                    imageData: imageData,
                    mimeType: "image/jpeg",
                    updateStage: updateStage
                )
                try Task.checkCancellation()
                await updateStage(.preparingPreview)
                await MainActor.run {
                    guard businessCardTaskID == taskID else {
                        return
                    }
                    businessCardPreview = result
                    finishProcessing(.businessCard)
                }
            } catch {
                await MainActor.run {
                    guard businessCardTaskID == taskID else {
                        return
                    }
                    finishProcessing(.businessCard)
                    guard !isCancellationError(error) else {
                        return
                    }
                    businessCardError = GeminiServiceError.message(
                        for: error,
                        fallback: "명함을 분석하지 못했습니다. 이미지를 다시 선택해 주세요."
                    )
                }
            }
        }
    }

    private func processDocumentImage(_ imageData: Data) {
        guard !isProcessingDocumentScan else {
            return
        }

        isProcessingDocumentScan = true
        documentScanError = nil
        let taskID = UUID()
        documentScanTaskID = taskID
        setProcessingStage(.preparingInput, for: .documentScan)

        documentScanTask = Task {
            do {
                let updateStage = stageUpdater(for: .documentScan, taskID: taskID)
                let result = try await GeminiDocumentScanService.scan(
                    imageData: imageData,
                    mimeType: "image/jpeg",
                    updateStage: updateStage
                )
                try Task.checkCancellation()
                await updateStage(.preparingPreview)
                await MainActor.run {
                    guard documentScanTaskID == taskID else {
                        return
                    }
                    documentScanPreview = result
                    finishProcessing(.documentScan)
                }
            } catch {
                await MainActor.run {
                    guard documentScanTaskID == taskID else {
                        return
                    }
                    finishProcessing(.documentScan)
                    guard !isCancellationError(error) else {
                        return
                    }
                    documentScanError = GeminiServiceError.message(
                        for: error,
                        fallback: "문서를 분석하지 못했습니다. 이미지를 다시 선택해 주세요."
                    )
                }
            }
        }
    }

    private func processFile(_ url: URL) {
        guard !isProcessingFileSummary else {
            return
        }

        // 파일 요약은 security-scoped resource 접근과 파일 읽기를 Task 안에서 처리합니다.
        isProcessingFileSummary = true
        fileSummaryError = nil
        let taskID = UUID()
        fileSummaryTaskID = taskID
        setProcessingStage(.preparingInput, for: .fileSummary)

        fileSummaryTask = Task {
            do {
                let updateStage = stageUpdater(for: .fileSummary, taskID: taskID)
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let input: FileSummaryInput
                do {
                    input = try FileSummaryInputReader.read(url: url)
                } catch {
                    await MainActor.run {
                        guard fileSummaryTaskID == taskID else {
                            return
                        }
                        finishProcessing(.fileSummary)
                        guard !isCancellationError(error) else {
                            return
                        }
                        fileSummaryError = GeminiServiceError.message(
                            for: error,
                            fallback: "파일을 읽을 수 없습니다. PDF, TXT, RTF, DOCX 파일을 선택해 주세요."
                        )
                    }
                    return
                }
                try Task.checkCancellation()
                let result = try await GeminiFileSummaryService.summarize(
                    fileName: input.fileName,
                    mimeType: input.mimeType,
                    text: input.text,
                    fileData: input.text.isEmpty ? input.data : nil,
                    updateStage: updateStage
                )
                try Task.checkCancellation()
                await updateStage(.preparingPreview)
                await MainActor.run {
                    guard fileSummaryTaskID == taskID else {
                        return
                    }
                    fileSummaryPreview = result
                    finishProcessing(.fileSummary)
                }
            } catch {
                await MainActor.run {
                    guard fileSummaryTaskID == taskID else {
                        return
                    }
                    finishProcessing(.fileSummary)
                    guard !isCancellationError(error) else {
                        return
                    }
                    fileSummaryError = GeminiServiceError.message(
                        for: error,
                        fallback: "파일을 요약하지 못했습니다. 파일 형식이나 내용을 확인해 주세요."
                    )
                }
            }
        }
    }

    private func processAudio(_ data: Data, mimeType: String, mode: MeetingSummaryMode) {
        guard !isProcessingMeeting else {
            return
        }

        isProcessingMeeting = true
        meetingError = nil
        let taskID = UUID()
        meetingTaskID = taskID
        setProcessingStage(.preparingInput, for: .meetingSummary)

        meetingTask = Task {
            do {
                let updateStage = stageUpdater(for: .meetingSummary, taskID: taskID)
                let result = try await GeminiMeetingSummaryService.summarize(
                    audioData: data,
                    mimeType: mimeType,
                    mode: mode,
                    updateStage: updateStage
                )
                try Task.checkCancellation()
                await updateStage(.preparingPreview)
                await MainActor.run {
                    guard meetingTaskID == taskID else {
                        return
                    }
                    meetingPreview = result
                    finishProcessing(.meetingSummary)
                }
            } catch {
                await MainActor.run {
                    guard meetingTaskID == taskID else {
                        return
                    }
                    finishProcessing(.meetingSummary)
                    guard !isCancellationError(error) else {
                        return
                    }
                    meetingError = GeminiServiceError.message(
                        for: error,
                        fallback: "회의 음성을 요약하지 못했습니다. 파일이나 녹음 상태를 확인해 주세요."
                    )
                }
            }
        }
    }

    private func isProcessing(_ feature: UtilityFeature) -> Bool {
        switch feature.kind {
        case .receipt:
            return isProcessingReceipt
        case .businessCard:
            return isProcessingBusinessCard
        case .handwritingOCR:
            return isProcessingOCR
        case .meetingSummary:
            return isProcessingMeeting
        case .documentScan:
            return isProcessingDocumentScan
        case .fileSummary:
            return isProcessingFileSummary
        }
    }

    private func processingMessage(for kind: UtilityFeatureKind) -> String {
        let stage = processingStage(for: kind)
        switch stage {
        case .preparingInput:
            return kind.preparingInputMessage
        case .requestingGemini:
            return "Gemini에 요청하고 있어요"
        case .parsingResponse:
            return "결과를 정리하고 있어요"
        case .preparingPreview:
            return "미리보기를 준비하고 있어요"
        }
    }

    private func processingStage(for kind: UtilityFeatureKind) -> AIProcessingStage {
        switch kind {
        case .receipt:
            return receiptStage
        case .businessCard:
            return businessCardStage
        case .handwritingOCR:
            return ocrStage
        case .meetingSummary:
            return meetingStage
        case .documentScan:
            return documentScanStage
        case .fileSummary:
            return fileSummaryStage
        }
    }

    private func setProcessingStage(_ stage: AIProcessingStage, for kind: UtilityFeatureKind) {
        switch kind {
        case .receipt:
            receiptStage = stage
        case .businessCard:
            businessCardStage = stage
        case .handwritingOCR:
            ocrStage = stage
        case .meetingSummary:
            meetingStage = stage
        case .documentScan:
            documentScanStage = stage
        case .fileSummary:
            fileSummaryStage = stage
        }
    }

    private func stageUpdater(for kind: UtilityFeatureKind, taskID: UUID) -> (AIProcessingStage) async -> Void {
        { stage in
            await MainActor.run {
                // 취소되었거나 새 작업으로 교체된 AI 작업의 늦은 콜백은 화면 상태에 반영하지 않습니다.
                guard currentTaskID(for: kind) == taskID else {
                    return
                }
                setProcessingStage(stage, for: kind)
            }
        }
    }

    private func currentTaskID(for kind: UtilityFeatureKind) -> UUID? {
        switch kind {
        case .receipt:
            return receiptTaskID
        case .businessCard:
            return businessCardTaskID
        case .handwritingOCR:
            return ocrTaskID
        case .meetingSummary:
            return meetingTaskID
        case .documentScan:
            return documentScanTaskID
        case .fileSummary:
            return fileSummaryTaskID
        }
    }

    private func setImageProcessingError(for kind: UtilityFeatureKind, message: String) {
        switch kind {
        case .receipt:
            receiptError = message
        case .businessCard:
            businessCardError = message
        case .handwritingOCR:
            ocrError = message
        case .meetingSummary:
            break
        case .documentScan:
            documentScanError = message
        case .fileSummary:
            break
        }
    }

    private func cancelProcessing(_ kind: UtilityFeatureKind) {
        // Task.cancel()만으로는 UI가 바로 닫히지 않으므로 화면 상태도 함께 정리합니다.
        task(for: kind)?.cancel()
        finishProcessing(kind)
    }

    private func finishProcessing(_ kind: UtilityFeatureKind) {
        // 작업이 끝나면 Task, taskID, 단계 문구, loading flag를 한 번에 초기화합니다.
        switch kind {
        case .receipt:
            receiptTask = nil
            receiptTaskID = nil
            receiptStage = .preparingInput
            isProcessingReceipt = false
        case .businessCard:
            businessCardTask = nil
            businessCardTaskID = nil
            businessCardStage = .preparingInput
            isProcessingBusinessCard = false
        case .handwritingOCR:
            ocrTask = nil
            ocrTaskID = nil
            ocrStage = .preparingInput
            isProcessingOCR = false
        case .meetingSummary:
            meetingTask = nil
            meetingTaskID = nil
            meetingStage = .preparingInput
            isProcessingMeeting = false
        case .documentScan:
            documentScanTask = nil
            documentScanTaskID = nil
            documentScanStage = .preparingInput
            isProcessingDocumentScan = false
        case .fileSummary:
            fileSummaryTask = nil
            fileSummaryTaskID = nil
            fileSummaryStage = .preparingInput
            isProcessingFileSummary = false
        }
    }

    private func task(for kind: UtilityFeatureKind) -> Task<Void, Never>? {
        switch kind {
        case .receipt:
            return receiptTask
        case .businessCard:
            return businessCardTask
        case .handwritingOCR:
            return ocrTask
        case .meetingSummary:
            return meetingTask
        case .documentScan:
            return documentScanTask
        case .fileSummary:
            return fileSummaryTask
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let geminiError = error as? GeminiServiceError,
           case .network(.cancelled) = geminiError {
            return true
        }
        return false
    }
}

private enum UtilityFeatureKind {
    case documentScan
    case fileSummary
    case receipt
    case businessCard
    case handwritingOCR
    case meetingSummary

    var preparingInputMessage: String {
        switch self {
        case .receipt, .businessCard, .handwritingOCR, .documentScan:
            return "이미지를 준비하고 있어요"
        case .meetingSummary:
            return "음성을 준비하고 있어요"
        case .fileSummary:
            return "파일을 읽고 있어요"
        }
    }

    var ambientColors: [Color] {
        switch self {
        case .documentScan:
            return [
                Color(red: 0.20, green: 0.58, blue: 1.0),
                Color(red: 0.66, green: 0.86, blue: 1.0),
                Color(red: 0.84, green: 0.86, blue: 0.92)
            ]
        case .fileSummary:
            return [
                Color(red: 0.38, green: 0.42, blue: 1.0),
                Color(red: 0.18, green: 0.88, blue: 0.76),
                Color(red: 0.72, green: 0.48, blue: 1.0)
            ]
        case .receipt:
            return [
                Color(red: 0.30, green: 0.92, blue: 0.68),
                Color(red: 0.78, green: 0.95, blue: 0.38),
                Color(red: 0.20, green: 0.68, blue: 0.98)
            ]
        case .businessCard:
            return [
                Color(red: 0.48, green: 0.46, blue: 1.0),
                Color(red: 0.78, green: 0.34, blue: 0.96),
                Color(red: 0.24, green: 0.70, blue: 1.0)
            ]
        case .handwritingOCR:
            return [
                Color(red: 0.22, green: 0.56, blue: 1.0),
                Color(red: 0.22, green: 0.94, blue: 0.88),
                Color(red: 0.68, green: 0.48, blue: 1.0)
            ]
        case .meetingSummary:
            return [
                Color(red: 1.0, green: 0.54, blue: 0.26),
                Color(red: 1.0, green: 0.38, blue: 0.66),
                Color(red: 0.58, green: 0.42, blue: 1.0)
            ]
        }
    }

    var accentLabel: String {
        switch self {
        case .documentScan:
            return "Document intelligence"
        case .fileSummary:
            return "File intelligence"
        case .receipt:
            return "Scan expenses"
        case .businessCard:
            return "Smart contacts"
        case .handwritingOCR:
            return "Handwriting to note"
        case .meetingSummary:
            return "Meeting intelligence"
        }
    }

    var listAccentColor: Color {
        switch self {
        case .handwritingOCR:
            return .cyan
        case .meetingSummary:
            return .orange
        case .fileSummary:
            return .blue
        case .documentScan:
            return .indigo
        case .receipt:
            return .green
        case .businessCard:
            return .pink
        }
    }
}

private enum UtilityFeatureSection: CaseIterable, Identifiable, Equatable {
    case convertToNote
    case organizeDocument

    var id: String { title }

    var title: String {
        switch self {
        case .convertToNote:
            return "메모로 바꾸기"
        case .organizeDocument:
            return "문서 정리하기"
        }
    }

}

private struct UtilityFeature: Identifiable {
    let id = UUID()
    let kind: UtilityFeatureKind
    let section: UtilityFeatureSection
    let title: String
    let listSubtitle: String
    let subtitle: String
    let description: String
    let systemImage: String
    let inputLabel: String
    let providerLabel = "Gemini"

    var isAvailable: Bool {
        true
    }
}

private struct UtilityFeatureSectionView: View {
    let section: UtilityFeatureSection
    let features: [UtilityFeature]
    let showsProviderFooter: Bool
    let isProcessing: (UtilityFeature) -> Bool
    let processImage: (UIImage, UtilityFeatureKind) -> Void
    let processAudio: (Data, String, MeetingSummaryMode) -> Void
    let processFile: (URL) -> Void

    var body: some View {
        Section {
            ForEach(features) { feature in
                NavigationLink {
                    UtilityFeatureDetailView(
                        feature: feature,
                        isProcessing: isProcessing(feature),
                        processImage: processImage,
                        processAudio: processAudio,
                        processFile: processFile
                    )
                } label: {
                    UtilityFeatureRow(
                        feature: feature,
                        isProcessing: isProcessing(feature)
                    )
                }
            }
        } header: {
            Text(section.title)
                .textCase(nil)
        } footer: {
            if showsProviderFooter {
                Text("AI 처리는 Gemini를 사용합니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct UtilityFeatureRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let feature: UtilityFeature
    let isProcessing: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: feature.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    feature.kind.listAccentColor,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.title)
                        .font(.body)
                        .foregroundStyle(.primary)

                    metadata
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(feature.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                metadata
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(feature.isAvailable ? 1 : 0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(feature.title), \(feature.listSubtitle)")
        .accessibilityValue(isProcessing ? "처리 중" : "입력 형식 \(feature.inputLabel)")
    }

    @ViewBuilder
    private var metadata: some View {
        if isProcessing {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                Text("처리 중")
            }
            .font(.footnote)
            .foregroundStyle(feature.kind.listAccentColor)
        } else {
            Text(feature.inputLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct UtilityFeatureBadge: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(NoteFlowDesign.mute)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(NoteFlowDesign.canvas, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(NoteFlowDesign.hairlineSoft, lineWidth: 1)
            )
    }
}

private struct UtilityFeatureDetailView: View {
    let feature: UtilityFeature
    let isProcessing: Bool
    let processImage: (UIImage, UtilityFeatureKind) -> Void
    let processAudio: (Data, String, MeetingSummaryMode) -> Void
    let processFile: (URL) -> Void

    @State private var showsImageSourceDialog = false
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    @State private var showsMeetingModeDialog = false
    @State private var showsAudioSourceDialog = false
    @State private var showsRecording = false
    @State private var showsFileImporter = false
    @State private var activeFileImporter: UtilityFileImportPurpose?
    @State private var selectedMeetingMode: MeetingSummaryMode = .transcriptAndSummary
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var localError: String?

    var body: some View {
        ZStack {
            UtilityFeatureAmbientBackground(colors: feature.kind.ambientColors)

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    UtilityFeatureHero(feature: feature)
                    bottomAction
                }
                .padding(.horizontal, 22)
                .padding(.top, 26)
                .padding(.bottom, 72)
            }

            actionPickerOverlay
        }
        .background(NoteFlowDesign.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(
            isPresented: $showsPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, newValue in
            loadPhotoItem(newValue)
        }
        .sheet(isPresented: $showsCamera) {
            CameraPickerView { image in
                showsCamera = false
                guard let image else {
                    return
                }
                processImage(image, feature.kind)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsRecording) {
            VoiceRecordingView(
                finish: { url in
                    showsRecording = false
                    loadAudioFile(url)
                },
                cancel: {
                    showsRecording = false
                }
            )
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: activeFileImporterContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert("이미지 선택 실패", isPresented: Binding(
            get: { localError != nil },
            set: { isPresented in
                if !isPresented {
                    localError = nil
                }
            }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(localError ?? "")
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: showsImageSourceDialog)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: showsMeetingModeDialog)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: showsAudioSourceDialog)
    }

    @ViewBuilder
    private var actionPickerOverlay: some View {
        if showsImageSourceDialog {
            UtilityActionPickerOverlay(
                title: "이미지 선택",
                message: "\(feature.title)에 사용할 이미지를 선택하세요.",
                options: [
                    UtilityActionPickerOption(
                        title: "사진첩에서 가져오기",
                        subtitle: "저장된 사진에서 선택",
                        systemImage: "photo.on.rectangle"
                    ) {
                        dismissActionPickers()
                        presentAfterPickerDismiss {
                            showsPhotoPicker = true
                        }
                    },
                    UtilityActionPickerOption(
                        title: "카메라로 찍기",
                        subtitle: "새 사진을 촬영",
                        systemImage: "camera"
                    ) {
                        dismissActionPickers()
                        presentAfterPickerDismiss {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                showsCamera = true
                            } else {
                                localError = "이 기기에서는 카메라를 사용할 수 없습니다."
                            }
                        }
                    }
                ],
                dismiss: dismissActionPickers
            )
        } else if showsMeetingModeDialog {
            UtilityActionPickerOverlay(
                title: "결과 선택",
                message: "회의 음성을 어떤 형태로 정리할까요?",
                options: MeetingSummaryMode.allCases.map { mode in
                    UtilityActionPickerOption(
                        title: mode.title,
                        subtitle: mode.description,
                        systemImage: iconName(for: mode)
                    ) {
                        selectedMeetingMode = mode
                        dismissActionPickers()
                        presentAfterPickerDismiss {
                            showsAudioSourceDialog = true
                        }
                    }
                },
                dismiss: dismissActionPickers
            )
        } else if showsAudioSourceDialog {
            UtilityActionPickerOverlay(
                title: "음성 선택",
                message: "분석할 회의 음성을 준비하세요.",
                options: [
                    UtilityActionPickerOption(
                        title: "바로 녹음",
                        subtitle: "지금 회의를 녹음",
                        systemImage: "waveform"
                    ) {
                        dismissActionPickers()
                        presentAfterPickerDismiss {
                            showsRecording = true
                        }
                    },
                    UtilityActionPickerOption(
                        title: "음성 파일 가져오기",
                        subtitle: "기존 오디오 파일 선택",
                        systemImage: "folder"
                    ) {
                        dismissActionPickers()
                        activeFileImporter = .audio
                        presentAfterPickerDismiss {
                            showsFileImporter = true
                        }
                    }
                ],
                dismiss: dismissActionPickers
            )
        }
    }

    private var bottomAction: some View {
        VStack(spacing: 10) {
            Button {
                if feature.isAvailable && !isProcessing {
                    startFeature()
                }
            } label: {
                Text(feature.isAvailable ? (isProcessing ? "분석 중" : "시작") : "준비 중")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(feature.isAvailable && !isProcessing ? .white : NoteFlowDesign.mute)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(buttonBackground, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(feature.isAvailable && !isProcessing ? 0.26 : 0), lineWidth: 1)
                    )
                    .shadow(
                        color: feature.isAvailable && !isProcessing ? feature.kind.ambientColors[0].opacity(0.24) : .clear,
                        radius: 18,
                        x: 0,
                        y: 10
                    )
            }
            .buttonStyle(.plain)
            .disabled(!feature.isAvailable || isProcessing)
        }
        .padding(.top, 4)
    }

    private func startFeature() {
        // 기능마다 필요한 입력 방식이 달라서 시작 버튼에서 선택 화면을 분기합니다.
        switch feature.kind {
        case .receipt, .businessCard, .handwritingOCR, .documentScan:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                showsImageSourceDialog = true
            }
        case .meetingSummary:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                showsMeetingModeDialog = true
            }
        case .fileSummary:
            activeFileImporter = .fileSummary
            showsFileImporter = true
        }
    }

    private func dismissActionPickers() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            showsImageSourceDialog = false
            showsMeetingModeDialog = false
            showsAudioSourceDialog = false
        }
    }

    private func presentAfterPickerDismiss(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            action()
        }
    }

    private func iconName(for mode: MeetingSummaryMode) -> String {
        switch mode {
        case .transcript:
            return "text.alignleft"
        case .summary:
            return "text.badge.checkmark"
        case .transcriptAndSummary:
            return "doc.text.magnifyingglass"
        }
    }

    private var buttonBackground: AnyShapeStyle {
        if feature.isAvailable && !isProcessing {
            AnyShapeStyle(LinearGradient(
                colors: [NoteFlowDesign.ink, NoteFlowDesign.charcoal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        } else {
            AnyShapeStyle(NoteFlowDesign.softCloud)
        }
    }

    private func loadPhotoItem(_ item: PhotosPickerItem?) {
        guard let item else {
            return
        }

        Task {
            defer {
                Task { @MainActor in
                    selectedPhotoItem = nil
                }
            }

            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    await MainActor.run {
                        localError = "이미지를 불러오지 못했습니다."
                    }
                    return
                }

                await MainActor.run {
                    processImage(image, feature.kind)
                }
            } catch {
                await MainActor.run {
                    localError = "이미지를 불러오지 못했습니다."
                }
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        defer {
            activeFileImporter = nil
        }

        do {
            guard let url = try result.get().first else {
                return
            }

            switch activeFileImporter {
            case .audio:
                loadAudioFile(url)
            case .fileSummary:
                processFile(url)
            case nil:
                return
            }
        } catch {
            switch activeFileImporter {
            case .audio:
                localError = "음성 파일을 불러오지 못했습니다."
            case .fileSummary:
                localError = "파일을 불러오지 못했습니다."
            case nil:
                return
            }
        }
    }

    private func loadAudioFile(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                localError = "음성 파일이 비어 있습니다."
                return
            }
            processAudio(data, mimeType(for: url), selectedMeetingMode)
        } catch {
            localError = "음성 파일을 불러오지 못했습니다."
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a", "mp4":
            return "audio/mp4"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "aac":
            return "audio/aac"
        default:
            return "audio/mp4"
        }
    }

    private var activeFileImporterContentTypes: [UTType] {
        switch activeFileImporter {
        case .audio:
            return audioContentTypes
        case .fileSummary:
            return fileSummaryContentTypes
        case nil:
            return [.item]
        }
    }

    private var audioContentTypes: [UTType] {
        var types: [UTType] = [.audio, .mpeg4Audio, .mp3, .wav, .item]
        if let m4a = UTType(filenameExtension: "m4a") {
            types.append(m4a)
        }
        if let aac = UTType(filenameExtension: "aac") {
            types.append(aac)
        }
        return types
    }

    private var fileSummaryContentTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .text, .rtf]
        if let docx = UTType(filenameExtension: "docx") {
            types.append(docx)
        }
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        return types
    }
}

private enum UtilityFileImportPurpose {
    case audio
    case fileSummary
}

private struct UtilityActionPickerOption: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void
}

private struct UtilityActionPickerOverlay: View {
    let title: String
    let message: String
    let options: [UtilityActionPickerOption]
    let dismiss: () -> Void
    private let bottomPanelClearance: CGFloat = 108

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(NoteFlowDesign.ink)

                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(NoteFlowDesign.mute)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 10)

                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NoteFlowDesign.mute)
                            .frame(width: 30, height: 30)
                            .background(NoteFlowDesign.softCloud, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("닫기")
                }

                VStack(spacing: 10) {
                    ForEach(options) { option in
                        Button(action: option.action) {
                            HStack(spacing: 12) {
                                Image(systemName: option.systemImage)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(NoteFlowDesign.ink)
                                    .frame(width: 38, height: 38)
                                    .background(NoteFlowDesign.canvas, in: Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(NoteFlowDesign.hairlineSoft, lineWidth: 1)
                                    )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.title)
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(NoteFlowDesign.ink)

                                    Text(option.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(NoteFlowDesign.mute)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 8)

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(NoteFlowDesign.hairline)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(NoteFlowDesign.softCloud, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(NoteFlowDesign.canvas.opacity(0.82))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 30, x: 0, y: 18)
            .padding(.horizontal, 18)
            .padding(.bottom, bottomPanelClearance)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }
}

private struct UtilityFeatureAmbientBackground: View {
    let colors: [Color]
    @State private var animate = false

    var body: some View {
        ZStack {
            NoteFlowDesign.canvas

            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors[safe: 0].opacity(0.22), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 210
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: animate ? 110 : -120, y: animate ? -190 : -120)
                .scaleEffect(animate ? 1.08 : 0.9)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors[safe: 1].opacity(0.18), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 240
                    )
                )
                .frame(width: 420, height: 420)
                .offset(x: animate ? -120 : 110, y: animate ? 120 : 210)
                .scaleEffect(animate ? 0.9 : 1.12)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors[safe: 2].opacity(0.14), .clear],
                        center: .center,
                        startRadius: 6,
                        endRadius: 180
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: animate ? 46 : -36, y: animate ? 6 : -18)
                .scaleEffect(animate ? 1.12 : 0.88)
        }
        .blur(radius: 28)
        .saturation(1.08)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.8).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

private struct UtilityFeatureHero: View {
    let feature: UtilityFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            icon

            VStack(alignment: .leading, spacing: 12) {
                Text(feature.kind.accentLabel.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NoteFlowDesign.mute)

                HStack(spacing: 8) {
                    UtilityFeatureBadge(text: feature.inputLabel, systemImage: inputSystemImage)
                    UtilityFeatureBadge(text: feature.providerLabel, systemImage: "sparkles")
                }

                Text(feature.title)
                    .font(.system(size: 38, weight: .black))
                    .foregroundStyle(NoteFlowDesign.ink)
                    .tracking(0)
                    .fixedSize(horizontal: false, vertical: true)

                Text(feature.description)
                    .font(.system(size: 17, weight: .regular))
                    .lineSpacing(5)
                    .foregroundStyle(NoteFlowDesign.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    feature.kind.ambientColors[0].opacity(0.22),
                                    feature.kind.ambientColors[1].opacity(0.10),
                                    .white.opacity(0.36)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.58), lineWidth: 1)
                )
                .shadow(color: feature.kind.ambientColors[0].opacity(0.18), radius: 24, x: 0, y: 12)

            Image(systemName: feature.systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(NoteFlowDesign.ink)
        }
        .frame(width: 88, height: 88)
    }

    private var inputSystemImage: String {
        switch feature.inputLabel {
        case "음성":
            return "waveform"
        case "파일":
            return "doc"
        default:
            return "photo"
        }
    }
}

private extension Array where Element == Color {
    subscript(safe index: Int) -> Color {
        guard indices.contains(index) else {
            return .clear
        }
        return self[index]
    }
}

private extension UIImage {
    func normalizedJPEGData(maxDimension: CGFloat) -> Data? {
        let longestSide = max(size.width, size.height)
        let scale = longestSide > maxDimension ? maxDimension / longestSide : 1
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let rendered = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: 0.86)
    }
}

#Preview {
    NavigationStack {
        UtilitiesView(
            saveOCRResult: { _ in },
            saveMeetingSummaryResult: { _ in },
            saveReceiptScanResult: { _ in },
            saveBusinessCardScanResult: { _ in },
            saveDocumentScanResult: { _ in },
            saveFileSummaryResult: { _ in }
        )
    }
}
