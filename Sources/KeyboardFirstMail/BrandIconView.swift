import AppKit
import SwiftUI

enum KeyboardMailBrandAssets {
    static var dockIcon: NSImage? {
        image(named: "KeyboardMailIcon", extension: "icns")
    }

    static var titlebarIcon: NSImage? {
        image(named: "KeyboardMailTitlebar", extension: "png") ?? dockIcon
    }

    private static func image(named name: String, extension fileExtension: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

struct KeyboardMailBrandIcon: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = KeyboardMailBrandAssets.titlebarIcon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                KeyboardMailVectorMark()
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mail")
    }
}

private struct KeyboardMailVectorMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: side * 0.21875, style: .continuous)
                    .fill(.black)

                KeyboardMailCursorShape()
                    .fill(.white)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

private struct KeyboardMailCursorShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 1024
        let origin = CGPoint(
            x: rect.midX - (512 * scale),
            y: rect.midY - (512 * scale)
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + (x * scale), y: origin.y + (y * scale))
        }

        let cursorSourceCenter = CGPoint(x: 42.509169585, y: 43.163415306)
        let cursorCanvasCenter = CGPoint(x: 488, y: 536)
        let cursorSourceScale: CGFloat = 24.807151
        func cursorPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            point(
                cursorCanvasCenter.x - ((x - cursorSourceCenter.x) * cursorSourceScale),
                cursorCanvasCenter.y + ((y - cursorSourceCenter.y) * cursorSourceScale)
            )
        }

        var path = Path()
        path.move(to: cursorPoint(32.6445, 32.2549))
        path.addCurve(
            to: cursorPoint(31.5996, 33.3037),
            control1: cursorPoint(31.9921, 32.0027),
            control2: cursorPoint(31.3503, 32.6469)
        )
        path.addLine(to: cursorPoint(39.3145, 53.6045))
        path.addCurve(
            to: cursorPoint(40.877, 53.3145),
            control1: cursorPoint(39.6345, 54.4468),
            control2: cursorPoint(40.877, 54.2162)
        )
        path.addLine(to: cursorPoint(40.877, 41.6836))
        path.addLine(to: cursorPoint(52.665, 41.6836))
        path.addCurve(
            to: cursorPoint(52.9551, 40.1133),
            control1: cursorPoint(53.5605, 41.6836),
            control2: cursorPoint(53.7908, 40.4368)
        )
        path.closeSubpath()
        return path
    }
}
