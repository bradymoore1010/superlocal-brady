import AppKit
import SwiftUI

struct InlineMessageBodyView: View {
    let text: String
    let images: [InlineDraftImage]

    init(body: String, images: [InlineDraftImage]) {
        text = body
        self.images = images
    }

    private var segments: [String] {
        text.components(separatedBy: MailDraftSerializer.inlineImageMarker)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(segments.indices, id: \.self) { index in
                let segment = segments[index].trimmingCharacters(in: .newlines)
                if !segment.isEmpty {
                    Text(linkified(segment))
                        .font(MailTheme.font(14))
                        .tracking(-0.1)
                        .lineSpacing(3)
                        .foregroundStyle(MailTheme.text)
                        .textSelection(.enabled)
                }

                if index < images.count {
                    InlineMessageImage(image: images[index])
                }
            }
        }
    }

    private func linkified(_ value: String) -> AttributedString {
        let attributed = NSMutableAttributedString(string: value)
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return AttributedString(attributed) }

        let range = NSRange(location: 0, length: attributed.length)
        for match in detector.matches(in: value, range: range) {
            guard let url = match.url else { continue }
            attributed.addAttributes([
                .link: url,
                .foregroundColor: NSColor(calibratedRed: 41 / 255, green: 41 / 255, blue: 41 / 255, alpha: 1),
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: match.range)
        }
        return AttributedString(attributed)
    }
}

private struct InlineMessageImage: View {
    let image: InlineDraftImage

    var body: some View {
        Group {
            if let nativeImage = NSImage(data: image.data) {
                Image(nsImage: nativeImage)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        maxWidth: image.displaySize.maximumSize.width,
                        maxHeight: image.displaySize.maximumSize.height,
                        alignment: .leading
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MailTheme.border, lineWidth: 1)
                    }
            } else {
                Text("[Image: \(image.name)]")
                    .font(MailTheme.font(13))
                    .foregroundStyle(MailTheme.secondaryText)
            }
        }
        .accessibilityLabel("Embedded image, \(image.name)")
    }
}

struct AttachmentStrip: View {
    let attachments: [DraftAttachment]
    let onRemove: (DraftAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 7) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MailTheme.secondaryText)

                        Text(attachment.name)
                            .font(MailTheme.font(12, weight: .medium))
                            .foregroundStyle(MailTheme.text)
                            .lineLimit(1)

                        if let sizeLabel = attachment.sizeLabel {
                            Text(sizeLabel)
                                .font(MailTheme.font(12))
                                .foregroundStyle(MailTheme.mutedText)
                        }

                        Button {
                            onRemove(attachment)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(MailTheme.mutedText)
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(attachment.name)")
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(MailTheme.secondarySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MailTheme.border, lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden)
        .frame(height: 36)
    }
}

struct MessageAttachmentStrip: View {
    let names: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(names, id: \.self) { name in
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 11, weight: .medium))
                    Text(name)
                        .font(MailTheme.font(12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(MailTheme.secondaryText)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(MailTheme.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MailTheme.border, lineWidth: 1)
                }
            }
        }
    }
}
