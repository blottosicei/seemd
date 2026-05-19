import Foundation
import Markdown

// Self-test cases for the Markdown parsing core (US-002). Wired into
// Sources/seemd-selftest/main.swift by the maintainer.

/// Collect every descendant node of `root` in document order.
private func allNodes(_ root: Markup) -> [Markup] {
    MarkdownDocument.depthFirst(root)
}

public func parsingCases() -> [TestCase] {
    [
        TestCase("parsing/heading-levels-and-order") { t in
            let md = """
            # Title
            ## Section A
            ### Sub A1
            ## Section B
            """
            let doc = MarkdownDocument(md)
            let levels = doc.headings.map { $0.level }
            let texts = doc.headings.map { $0.text }
            t.expectEqual(levels, [1, 2, 3, 2], "heading levels in document order")
            t.expectEqual(texts, ["Title", "Section A", "Sub A1", "Section B"],
                          "heading text in document order")
        },

        TestCase("parsing/all-six-levels") { t in
            let md = """
            # h1
            ## h2
            ### h3
            #### h4
            ##### h5
            ###### h6
            """
            let doc = MarkdownDocument(md)
            t.expectEqual(doc.headings.map { $0.level }, [1, 2, 3, 4, 5, 6],
                          "levels 1...6 supported")
        },

        TestCase("parsing/slug-generation") { t in
            let md = "## Hello, World! & Friends"
            let doc = MarkdownDocument(md)
            t.expectEqual(doc.headings.count, 1, "one heading")
            t.expectEqual(doc.headings.first?.slug, "hello-world--friends",
                          "lowercase, spaces->-, strip punctuation")
        },

        TestCase("parsing/slug-strips-inline-formatting") { t in
            let md = "## The `code` and *emphasis* Heading"
            let doc = MarkdownDocument(md)
            t.expectEqual(doc.headings.first?.text, "The code and emphasis Heading",
                          "plain text strips inline markup")
            t.expectEqual(doc.headings.first?.slug, "the-code-and-emphasis-heading",
                          "slug from plain text")
        },

        TestCase("parsing/duplicate-slug-dedup") { t in
            let md = """
            # Setup
            # Setup
            # Setup
            # Other
            # Other
            """
            let doc = MarkdownDocument(md)
            t.expectEqual(doc.headings.map { $0.slug },
                          ["setup", "setup-1", "setup-2", "other", "other-1"],
                          "GitHub-style -1, -2 dedup per base slug")
        },

        TestCase("parsing/lists-present") { t in
            let md = """
            - alpha
            - beta
            - gamma

            1. one
            2. two
            """
            let doc = MarkdownDocument(md)
            let nodes = allNodes(doc.document)
            let unordered = nodes.contains { $0 is UnorderedList }
            let ordered = nodes.contains { $0 is OrderedList }
            let items = nodes.compactMap { $0 as? ListItem }.count
            t.expect(unordered, "unordered list parsed")
            t.expect(ordered, "ordered list parsed")
            t.expectEqual(items, 5, "five list items total")
        },

        TestCase("parsing/fenced-code-block-language") { t in
            let md = """
            Intro text.

            ```swift
            let x = 1
            print(x)
            ```
            """
            let doc = MarkdownDocument(md)
            let blocks = allNodes(doc.document).compactMap { $0 as? CodeBlock }
            t.expectEqual(blocks.count, 1, "one fenced code block")
            t.expectEqual(blocks.first?.language, "swift", "language info string")
            t.expect(blocks.first?.code.contains("print(x)") ?? false,
                     "code body preserved")
        },

        TestCase("parsing/gfm-table") { t in
            let md = """
            | Name | Age |
            | ---- | --- |
            | Ann  | 30  |
            | Bob  | 25  |
            """
            let doc = MarkdownDocument(md)
            let nodes = allNodes(doc.document)
            let tables = nodes.compactMap { $0 as? Table }
            t.expectEqual(tables.count, 1, "GFM table parsed")
            let rows = nodes.compactMap { $0 as? Table.Row }.count
            t.expectEqual(rows, 2, "two body rows")
            let head = nodes.compactMap { $0 as? Table.Head }.first
            t.expect(head != nil, "table head present")
            let headerCells = (head?.children.compactMap { $0 as? Table.Cell } ?? [])
                .map { $0.plainText }
            t.expectEqual(headerCells, ["Name", "Age"], "header cell text")
        },

        TestCase("parsing/task-list-items") { t in
            let md = """
            - [ ] todo one
            - [x] done two
            - regular item
            """
            let doc = MarkdownDocument(md)
            let items = allNodes(doc.document).compactMap { $0 as? ListItem }
            t.expectEqual(items.count, 3, "three list items")
            let unchecked = items.filter { $0.checkbox == .unchecked }.count
            let checked = items.filter { $0.checkbox == .checked }.count
            let none = items.filter { $0.checkbox == nil }.count
            t.expectEqual(unchecked, 1, "one unchecked task")
            t.expectEqual(checked, 1, "one checked task")
            t.expectEqual(none, 1, "one non-task item")
        },

        TestCase("parsing/strikethrough") { t in
            let md = "This is ~~deleted~~ text."
            let doc = MarkdownDocument(md)
            let strikes = allNodes(doc.document).compactMap { $0 as? Strikethrough }
            t.expectEqual(strikes.count, 1, "strikethrough parsed")
            t.expectEqual(strikes.first.map { MarkdownDocument.inlinePlainText($0) },
                          "deleted",
                          "strikethrough content (delimiters stripped)")
        }
    ]
}
