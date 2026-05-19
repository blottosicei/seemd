import Foundation
import Markdown

// Self-test cases for the render model (US-003). Wired into
// Sources/seemd-selftest/main.swift by the maintainer.

private func render(_ md: String) -> [RenderBlock] {
    RenderBuilder.build(MarkdownDocument(md))
}

public func renderCases() -> [TestCase] {
    [
        TestCase("render/heading-with-doc-slug-parity") { t in
            let md = """
            # Setup
            ## Setup
            ### Other Section
            """
            let doc = MarkdownDocument(md)
            let blocks = RenderBuilder.build(doc)
            let renderSlugs: [String] = blocks.compactMap {
                if case let .heading(_, slug, _) = $0 { return slug }
                return nil
            }
            t.expectEqual(renderSlugs, doc.headings.map { $0.slug },
                          "render heading slugs match doc.headings order")
            t.expectEqual(renderSlugs, ["setup", "setup-1", "other-section"],
                          "GitHub-style dedup preserved in render model")
            t.expectEqual(blocks.first,
                          .heading(level: 1, slug: "setup",
                                   inlines: [.text("Setup")]),
                          "first heading block shape")
        },

        TestCase("render/paragraph-inline-mix") { t in
            let md = "Plain *em* and **bold** and `code` and ~~gone~~ text."
            let blocks = render(md)
            t.expectEqual(blocks, [
                .paragraph([
                    .text("Plain "),
                    .emphasis([.text("em")]),
                    .text(" and "),
                    .strong([.text("bold")]),
                    .text(" and "),
                    .code("code"),
                    .text(" and "),
                    .strikethrough([.text("gone")]),
                    .text(" text.")
                ])
            ], "inline node mix")
        },

        TestCase("render/link-and-image-inlines") { t in
            let md = "See [the docs](https://example.com/d) and ![logo](img/logo.png)."
            let blocks = render(md)
            t.expectEqual(blocks, [
                .paragraph([
                    .text("See "),
                    .link(text: [.text("the docs")],
                          destination: "https://example.com/d"),
                    .text(" and "),
                    .image(alt: "logo", source: "img/logo.png"),
                    .text(".")
                ])
            ], "link destination + image alt/source")
        },

        TestCase("render/fenced-code-block-language") { t in
            let md = """
            ```swift
            let x = 1
            ```
            """
            let blocks = render(md)
            t.expectEqual(blocks,
                          [.codeBlock(language: "swift", code: "let x = 1\n")],
                          "fenced code with info-string language")
        },

        TestCase("render/indented-code-block-no-language") { t in
            let md = "    plain code\n"
            let blocks = render(md)
            t.expectEqual(blocks,
                          [.codeBlock(language: nil, code: "plain code\n")],
                          "indented code has no language")
        },

        TestCase("render/blockquote-recursive") { t in
            let md = """
            > Quoted para.
            >
            > > Nested quote.
            """
            let blocks = render(md)
            t.expectEqual(blocks, [
                .blockQuote([
                    .paragraph([.text("Quoted para.")]),
                    .blockQuote([.paragraph([.text("Nested quote.")])])
                ])
            ], "recursive block quote")
        },

        TestCase("render/unordered-list-nested") { t in
            let md = """
            - alpha
            - beta
              - beta-1
            """
            let blocks = render(md)
            t.expectEqual(blocks, [
                .unorderedList([
                    [.paragraph([.text("alpha")])],
                    [
                        .paragraph([.text("beta")]),
                        .unorderedList([[.paragraph([.text("beta-1")])]])
                    ]
                ])
            ], "nested unordered list -> recursive child blocks")
        },

        TestCase("render/ordered-list-start") { t in
            let md = """
            3. three
            4. four
            """
            let blocks = render(md)
            t.expectEqual(blocks, [
                .orderedList(start: 3, items: [
                    [.paragraph([.text("three")])],
                    [.paragraph([.text("four")])]
                ])
            ], "ordered list preserves start index")
        },

        TestCase("render/task-list-items") { t in
            let md = """
            - [ ] todo
            - [x] done
            - plain
            """
            let blocks = render(md)
            t.expectEqual(blocks, [
                .unorderedList([
                    [.taskListItem(checked: false,
                                   blocks: [.paragraph([.text("todo")])])],
                    [.taskListItem(checked: true,
                                   blocks: [.paragraph([.text("done")])])],
                    [.paragraph([.text("plain")])]
                ])
            ], "GFM task-list checkbox state")
        },

        TestCase("render/table-alignments") { t in
            let md = """
            | L    | C      | R     | D       |
            | :--- | :----: | ----: | ------- |
            | a    | b      | c     | d       |
            """
            let blocks = render(md)
            t.expectEqual(blocks, [
                .table(
                    header: [
                        [.text("L")], [.text("C")], [.text("R")], [.text("D")]
                    ],
                    rows: [[
                        [.text("a")], [.text("b")], [.text("c")], [.text("d")]
                    ]],
                    alignments: [.left, .center, .right, .none]
                )
            ], "GFM table header, rows, and column alignments")
        },

        TestCase("render/thematic-break") { t in
            let md = """
            Above.

            ---

            Below.
            """
            let blocks = render(md)
            t.expectEqual(blocks, [
                .paragraph([.text("Above.")]),
                .thematicBreak,
                .paragraph([.text("Below.")])
            ], "thematic break between paragraphs")
        },

        TestCase("render/soft-break-becomes-linebreak") { t in
            let md = "line one\nline two"
            let blocks = render(md)
            t.expectEqual(blocks, [
                .paragraph([
                    .text("line one"), .lineBreak, .text("line two")
                ])
            ], "soft break maps to lineBreak inline")
        }
    ]
}
