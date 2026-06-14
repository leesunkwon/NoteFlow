import UIKit
import SwiftUI

private final class WeakTextView {
    weak var value: UITextView?

    init(_ value: UITextView?) {
        self.value = value
    }
}

final class BlockTextFocusStore {
    private var textViews: [UUID: WeakTextView] = [:]

    func register(_ textView: UITextView, for blockID: UUID) {
        textViews[blockID] = WeakTextView(textView)
    }

    func unregister(_ textView: UITextView, for blockID: UUID) {
        guard textViews[blockID]?.value === textView else {
            return
        }
        textViews[blockID] = nil
    }

    @discardableResult
    func focus(_ blockID: UUID) -> Bool {
        guard let textView = textViews[blockID]?.value,
              textView.window != nil else {
            return false
        }

        if textView.becomeFirstResponder() {
            let end = ((textView.text ?? "") as NSString).length
            textView.selectedRange = NSRange(location: end, length: 0)
            return true
        }

        return false
    }
}

struct BlockTextInput: View {
    let blockID: UUID
    @Binding var text: String
    let placeholder: String
    let font: Font
    let uiFont: UIFont
    let textColor: Color
    let uiTextColor: UIColor
    let isReadOnly: Bool
    let isFocused: Bool
    let focusRequestID: Int
    let focusStore: BlockTextFocusStore
    let isStruckThrough: Bool
    let minHeight: CGFloat
    let verticalPadding: CGFloat
    let onFocus: () -> Void
    let onSubmit: (String) -> Void
    let onDeleteBackward: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, verticalPadding)
                    .allowsHitTesting(false)
            }

            BlockTextView(
                blockID: blockID,
                text: $text,
                font: uiFont,
                textColor: uiTextColor,
                isReadOnly: isReadOnly,
                isFocused: isFocused,
                focusRequestID: focusRequestID,
                focusStore: focusStore,
                isStruckThrough: isStruckThrough,
                minHeight: minHeight,
                onFocus: onFocus,
                onSubmit: onSubmit,
                onDeleteBackward: onDeleteBackward
            )
            .foregroundStyle(textColor)
        }
        .frame(minHeight: minHeight, alignment: .leading)
        .padding(.vertical, verticalPadding)
    }
}

struct BlockTextView: UIViewRepresentable {
    let blockID: UUID
    @Binding var text: String
    let font: UIFont
    let textColor: UIColor
    let isReadOnly: Bool
    let isFocused: Bool
    let focusRequestID: Int
    let focusStore: BlockTextFocusStore
    let isStruckThrough: Bool
    let minHeight: CGFloat
    let onFocus: () -> Void
    let onSubmit: (String) -> Void
    let onDeleteBackward: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.returnKeyType = .default
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        focusStore.register(textView, for: blockID)

        if textView.text != text {
            textView.text = text
        }

        textView.font = font
        textView.textColor = textColor
        textView.isEditable = !isReadOnly
        textView.isSelectable = !isReadOnly
        textView.typingAttributes = textAttributes

        if isStruckThrough, !textView.isFirstResponder {
            textView.attributedText = NSAttributedString(string: text, attributes: textAttributes)
        }

        if isFocused && !isReadOnly {
            if context.coordinator.appliedFocusRequestID != focusRequestID || !textView.isFirstResponder {
                context.coordinator.appliedFocusRequestID = focusRequestID
                requestFocus(for: textView)
            }
        } else if textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    private func requestFocus(for textView: UITextView, retryCount: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (retryCount == 0 ? 0 : 0.05)) {
            guard !textView.isFirstResponder else {
                return
            }

            guard textView.window != nil else {
                if retryCount < 3 {
                    requestFocus(for: textView, retryCount: retryCount + 1)
                }
                return
            }

            if textView.becomeFirstResponder() {
                let end = ((textView.text ?? "") as NSString).length
                textView.selectedRange = NSRange(location: end, length: 0)
            } else if retryCount < 3 {
                requestFocus(for: textView, retryCount: retryCount + 1)
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = max(proposal.width ?? uiView.bounds.width, 1)
        let fittingSize = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fittingSize.height, minHeight))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        coordinator.parent.focusStore.unregister(uiView, for: coordinator.parent.blockID)
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        if isStruckThrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextView
        var appliedFocusRequestID = -1

        init(parent: BlockTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocus()
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard text == "\n" else {
                if text.isEmpty,
                   range.length == 0,
                   (textView.text ?? "").isEmpty {
                    textView.resignFirstResponder()
                    parent.onDeleteBackward()
                    return false
                }
                return true
            }

            let currentText = textView.text ?? ""
            let nsText = currentText as NSString
            let splitStart = min(range.location, nsText.length)
            let splitEnd = min(range.location + range.length, nsText.length)
            let leadingText = nsText.substring(to: splitStart)
            let trailingText = nsText.substring(from: splitEnd)

            textView.text = leadingText
            parent.text = leadingText
            textView.resignFirstResponder()
            parent.onSubmit(trailingText)
            return false
        }
    }
}

extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let traits = fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any] ?? [:]
        var updatedTraits = traits
        updatedTraits[.weight] = weight
        let descriptor = fontDescriptor.addingAttributes([.traits: updatedTraits])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
