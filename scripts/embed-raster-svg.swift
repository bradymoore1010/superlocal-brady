import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: embed-raster-svg <input.png> <output.svg>\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let pngData = try Data(contentsOf: inputURL)
let encodedPNG = pngData.base64EncodedString()

// The selected chrome render is 1254 square. Embedding its source pixels is the
// only lossless way to preserve the photographic reflections in an SVG asset.
// The vector clip removes the render's opaque corner pixels for a clean app icon.
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1432 1432" role="img" aria-labelledby="title desc">
  <title id="title">Mail</title>
  <desc id="desc">A polished chrome cursor on a shaded graphite rounded square.</desc>
  <defs>
    <clipPath id="app-tile">
      <rect x="89" y="89" width="1254" height="1254" rx="260"/>
    </clipPath>
  </defs>
  <image x="89" y="89" width="1254" height="1254" preserveAspectRatio="xMidYMid slice" clip-path="url(#app-tile)" href="data:image/png;base64,\(encodedPNG)"/>
</svg>
"""

try svg.write(to: outputURL, atomically: true, encoding: .utf8)
