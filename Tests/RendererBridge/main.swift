import Foundation

let code = try HTMLRenderer.renderCode("let x = 1", lexer: "swift")
precondition(code.contains("chroma"))
let markdown = try HTMLRenderer.renderMarkdown("# Heading")
precondition(markdown.contains("Heading"))
do {
	_ = try HTMLRenderer.renderNotebook("not valid notebook JSON")
	fatalError("Notebook error was returned as HTML")
} catch let HTMLRendererError.rendererError(type, message) {
	precondition(type == "Jupyter Notebook" && !message.isEmpty)
}

for _ in 0 ..< 1000 {
	_ = try HTMLRenderer.renderMarkdown("Repeated preview")
}

print("PASS: real Go bridge rendering, error propagation and repeated result ownership")
