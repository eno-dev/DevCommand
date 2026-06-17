import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

enum QRCode {
    /// Render a crisp QR image for a string using CoreImage (no dependencies).
    static func image(from string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

/// A small qrcode button that pops a scannable QR of `url`. When `expoURL` is provided
/// (a Metro/Expo server), the popover offers an Expo/Browser toggle so scanning opens the
/// Expo Go / dev-client app via `exp://` instead of dropping into Safari.
struct QRButton: View {
    let url: String
    var expoURL: String? = nil
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "qrcode").font(.system(size: 14))
        }
        .buttonStyle(SubtleIconButtonStyle())
        .help("Show QR — scan to open on your phone")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            QRPopover(url: url, expoURL: expoURL)
        }
    }
}

/// QR popover body, reusable on its own — `QRButton` wraps it with a trigger, but rows
/// that already have a menu can present it directly from a menu item instead.
struct QRPopover: View {
    let url: String
    let expoURL: String?
    // Default to Expo when available — that's the whole point of scanning a Metro/Expo server.
    @State private var useExpo = true

    private var shownURL: String { (expoURL != nil && useExpo) ? expoURL! : url }
    private var caption: String {
        (expoURL != nil && useExpo) ? "Scan with Expo Go / dev client" : "Scan with your phone's camera"
    }

    var body: some View {
        VStack(spacing: Theme.s10) {
            if expoURL != nil {
                Picker("", selection: $useExpo) {
                    Text("Expo").tag(true)
                    Text("Browser").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            if let image = QRCode.image(from: shownURL) {
                // QR needs a light background + quiet zone to scan reliably.
                Image(nsImage: image)
                    .interpolation(.none).resizable()
                    .frame(width: 184, height: 184)
                    .padding(12)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text("Couldn't generate QR").foregroundStyle(.secondary)
            }
            Text(verbatim: shownURL)
                .font(Theme.mono(11)).foregroundStyle(.secondary).textSelection(.enabled)
                .lineLimit(1).truncationMode(.middle)
            Text(caption)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(Theme.s16)
        .frame(width: 232)
    }
}
