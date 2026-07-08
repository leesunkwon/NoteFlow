import SwiftData
import SwiftUI

// 앱의 최상위 화면으로, 실제 탭 기반 메인 화면을 시작합니다.
struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Folder.self, NotePage.self, TaskItem.self, NoteBlock.self], inMemory: true)
}
