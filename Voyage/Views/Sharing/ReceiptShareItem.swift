import SwiftUI
import UniformTypeIdentifiers

/// PNG flight receipt for the system share sheet.
struct ReceiptShareItem: Transferable {
    let pngData: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.pngData
        }
    }
}
