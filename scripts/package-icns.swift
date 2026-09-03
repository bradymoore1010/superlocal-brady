import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: package-icns <iconset-directory> <output.icns>\n", stderr)
    exit(2)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

// Include both standard and Retina representations so Finder and the Dock can
// select the correct bitmap without relying on iconutil.
let entries: [(type: String, filename: String)] = [
    ("icp4", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func fourCharacterCode(_ value: String) -> Data {
    precondition(value.utf8.count == 4)
    return Data(value.utf8)
}

func bigEndianData(_ value: UInt32) -> Data {
    var bigEndianValue = value.bigEndian
    return Data(bytes: &bigEndianValue, count: MemoryLayout<UInt32>.size)
}

var body = Data()
for entry in entries {
    let inputURL = iconsetURL.appendingPathComponent(entry.filename)
    let pngData = try Data(contentsOf: inputURL)
    let chunkLength = UInt32(8 + pngData.count)

    body.append(fourCharacterCode(entry.type))
    body.append(bigEndianData(chunkLength))
    body.append(pngData)
}

var iconData = Data()
iconData.append(fourCharacterCode("icns"))
iconData.append(bigEndianData(UInt32(8 + body.count)))
iconData.append(body)
try iconData.write(to: outputURL, options: .atomic)
