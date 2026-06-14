import SwiftUI

struct AIProcessingGradientOverlay: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.38)
                .overlay(Color.white.opacity(0.08))
                .ignoresSafeArea()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.24, green: 0.56, blue: 1.0).opacity(0.48),
                                .clear
                            ],
                            center: .center,
                            startRadius: 12,
                            endRadius: 190
                        )
                    )
                    .frame(width: 330, height: 330)
                    .offset(x: animate ? 92 : -84, y: animate ? -180 : -110)
                    .scaleEffect(animate ? 1.15 : 0.92)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.94, green: 0.24, blue: 0.82).opacity(0.44),
                                .clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 210
                        )
                    )
                    .frame(width: 370, height: 370)
                    .offset(x: animate ? -92 : 88, y: animate ? 116 : 190)
                    .scaleEffect(animate ? 0.94 : 1.18)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.24, green: 0.96, blue: 0.86).opacity(0.36),
                                .clear
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 180
                        )
                    )
                    .frame(width: 290, height: 290)
                    .offset(x: animate ? 42 : -36, y: animate ? 16 : -24)
                    .scaleEffect(animate ? 1.2 : 0.88)
            }
            .blur(radius: 32)
            .saturation(1.18)
            .ignoresSafeArea()
        }
        .allowsHitTesting(true)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

struct UtilityAIProcessingView: View {
    var message = "내용을 읽고 있어요"
    var cancel: (() -> Void)?

    var body: some View {
        ZStack {
            AIProcessingGradientOverlay()
                .background(NoteFlowDesign.canvas.ignoresSafeArea())

            VStack {
                HStack {
                    Spacer()

                    if let cancel {
                        Button(action: cancel) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(NoteFlowDesign.ink.opacity(0.72))
                                .frame(width: 42, height: 42)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(
                                    Circle()
                                        .stroke(NoteFlowDesign.hairlineSoft, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("AI 작업 취소")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                Spacer(minLength: 0)

                Text(message)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(NoteFlowDesign.ink.opacity(0.72))
                    .padding(.bottom, 120)
            }
        }
    }
}
