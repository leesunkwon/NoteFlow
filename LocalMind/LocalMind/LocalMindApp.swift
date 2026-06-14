//
//  LocalMindApp.swift
//  LocalMind
//
//  Created by sunkwon on 6/9/26.
//

import SwiftUI
import SwiftData

@main
struct LocalMindApp: App {
    private let modelContainer: ModelContainer?
    private let containerError: String?

    init() {
        do {
            modelContainer = try Self.makeModelContainer()
            containerError = nil
        } catch {
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
            let schema = Schema([
                Folder.self,
                NotePage.self,
                TaskItem.self,
                NoteBlock.self,
                DeletedNoteTombstone.self
            ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
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
                    try FileManager.default.removeItem(at: url)
                }
            }

            resetMessage = "로컬 저장소를 초기화했습니다. 앱을 다시 실행하세요."
        } catch {
            resetMessage = "초기화 실패: \(error.localizedDescription)\n\(String(describing: error))"
        }
    }
}
