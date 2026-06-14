import SwiftData
import SwiftUI

struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Folder.self, NotePage.self, TaskItem.self, NoteBlock.self], inMemory: true)
}
