import SwiftUI
import SwiftData

// 앱 시작 시 SwiftData 저장소를 만들고, 실패하면 복구 안내 화면으로 전환합니다.
@main
struct LocalMindApp: App {
    // 앱 전역에서 공유할 SwiftData 컨테이너입니다. 생성 실패 가능성이 있어 optional로 둡니다.
    private let modelContainer: ModelContainer?
    // 컨테이너 생성 실패 이유를 복구 화면에 보여주기 위한 문자열입니다.
    private let containerError: String?

    init() {
        do {
            // 앱 시작 시점에 저장소를 열어야 모든 화면의 @Query가 같은 컨테이너를 사용합니다.
            modelContainer = try Self.makeModelContainer()
            containerError = nil
        } catch {
            // SwiftData/CloudKit 설정 오류가 나면 앱을 죽이지 않고 복구 UI를 보여줍니다.
            modelContainer = nil
            containerError = "\(error.localizedDescription)\n\n\(String(describing: error))"
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                ContentView()
                    .modelContainer(modelContainer)
            } else {
                StorageRecoveryView(errorMessage: containerError ?? "알 수 없는 저장소 오류")
            }
        }
    }

    private static func makeModelContainer() throws -> ModelContainer {
        // CloudKit 동기화 대상 모델을 schema에 모두 등록해야 저장소가 정상 생성됩니다.
        let schema = Schema([
            Folder.self,
            NotePage.self,
            TaskItem.self,
            NoteBlock.self,
            DeletedNoteTombstone.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            // SwiftData는 이 private CloudKit DB를 통해 기기 간 메모 데이터를 동기화합니다.
            cloudKitDatabase: .private("iCloud.kotlinsun.LocalMind")
        )
        // 구성에 문제가 있으면 여기서 throw되고 StorageRecoveryView로 넘어갑니다.
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

private struct StorageRecoveryView: View {
    let errorMessage: String

    @State private var showsResetConfirmation = false
    @State private var resetMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 42))
                    .foregroundStyle(NoteFlowDesign.ink)

                Text("저장소를 열 수 없습니다")
                    .font(.title2.bold())

                Text("SwiftData 저장소 마이그레이션 또는 파일 오류로 앱 데이터를 불러오지 못했습니다.")
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(errorMessage)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)

                if let resetMessage {
                    Text(resetMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    showsResetConfirmation = true
                } label: {
                    Label("로컬 데이터 초기화", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Spacer()
            }
            .padding(24)
            .navigationTitle("저장소 복구")
            .navigationBarTitleDisplayMode(.inline)
            .alert("로컬 데이터를 초기화할까요?", isPresented: $showsResetConfirmation) {
                Button("취소", role: .cancel) { }
                Button("초기화", role: .destructive, action: resetLocalStore)
            } message: {
                Text("시뮬레이터 또는 기기에 저장된 NoteFlow 로컬 데이터가 삭제됩니다. 초기화 후 앱을 다시 실행하세요.")
            }
        }
        .tint(NoteFlowDesign.ink)
    }

    private func resetLocalStore() {
        do {
            // SwiftData 기본 SQLite store가 Application Support에 생성되므로 해당 위치를 찾습니다.
            let supportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let storeNames = [
                "default.store",
                "default.store-shm",
                "default.store-wal"
            ]

            for storeName in storeNames {
                let url = supportURL.appendingPathComponent(storeName)
                if FileManager.default.fileExists(atPath: url.path) {
                    // SQLite 본파일과 WAL/SHM 보조 파일을 같이 지워야 깨끗하게 초기화됩니다.
                    try FileManager.default.removeItem(at: url)
                }
            }

            resetMessage = "로컬 저장소를 초기화했습니다. 앱을 다시 실행하세요."
        } catch {
            resetMessage = "초기화 실패: \(error.localizedDescription)\n\(String(describing: error))"
        }
    }
}
