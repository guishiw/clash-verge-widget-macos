import AppKit
import SwiftUI

@main
struct PreviewRenderer {
    static func main() throws {
        let output = CommandLine.arguments.dropFirst().first ?? ".build/ClashVergeWidget-preview.png"
        let preview = ZStack {
            WidgetBackground(online: true)
            MediumStatusView(status: .placeholder)
        }
        .frame(width: 344, height: 164)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

        let renderer = ImageRenderer(content: preview)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: output), options: .atomic)
        print(output)
    }
}
