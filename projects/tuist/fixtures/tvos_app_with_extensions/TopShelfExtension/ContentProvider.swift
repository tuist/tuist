import TVServices

class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        completionHandler(TVTopShelfSectionedContent(sections: [
            TVTopShelfItemCollection(items: [
                makeItem(),
            ]),
        ]))
    }

    private func makeItem() -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: "tuist")
        item.title = "Test"
        return item
    }
}
