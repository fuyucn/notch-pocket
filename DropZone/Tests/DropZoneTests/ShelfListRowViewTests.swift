import Testing
import Foundation
@testable import DropZoneLib

@MainActor
struct ShelfListRowViewTests {
    private func item(
        name: String = "report.pdf",
        size: Int64 = 1_234_567,
        app: String? = "Finder",
        ext: String? = "pdf"
    ) -> ShelfItem {
        ShelfItem(
            originalURL: URL(fileURLWithPath: "/tmp/\(name)"),
            shelfURL: URL(fileURLWithPath: "/tmp/shelf/\(name)"),
            displayName: name,
            fileSize: size,
            sourceAppName: app,
            fileExtension: ext
        )
    }

    @Test
    func tagsIncludeAppTypeAndSize() {
        let row = ShelfListRowView(item: item(), onOpen: {}, onRemove: {})
        #expect(row.tags.count == 3)
        #expect(row.tags.contains("Finder"))
        #expect(row.tags.contains("PDF"))
    }

    @Test
    func missingAppHidesAppTag() {
        let row = ShelfListRowView(item: item(app: nil), onOpen: {}, onRemove: {})
        #expect(!row.tags.contains("Finder"))
        #expect(row.tags.count == 2)
    }

    @Test
    func zeroSizeHidesSizeTag() {
        let row = ShelfListRowView(item: item(size: 0), onOpen: {}, onRemove: {})
        #expect(row.tags.count == 2)
    }
}
