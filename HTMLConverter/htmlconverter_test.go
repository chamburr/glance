package main

import (
	"fmt"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/tdewolff/minify/v2"
	"github.com/tdewolff/minify/v2/html"
)

var minifier *minify.M

func minifyHTML(htmlString string) string {
	// Initialize minifier if necessary
	if minifier == nil {
		minifier = minify.New()
		minifier.Add("text/html", &html.Minifier{KeepEndTags: true, KeepQuotes: true})
	}

	minified, err := minifier.String("text/html", htmlString)
	if err != nil {
		panic(fmt.Sprintf("Could not minify HTML: %d", err))
	}

	return minified
}

func TestConvertCodeToHTML(t *testing.T) {
	source := `const print = (text) => console.log(text);
print("Hello world");`
	actual := convertToGoString(convertCodeToHTML(convertToCString(source), convertToCString("js")))
	actualTrimmed := strings.TrimSpace(actual)
	assert.True(t, strings.HasPrefix(actualTrimmed, `<pre tabindex="0" class="chroma">`))
	assert.True(t, strings.HasSuffix(actualTrimmed, `</pre>`))
}

func TestConvertMarkdownToHTML(t *testing.T) {
	source := `# Heading

Text`
	expected := "<h1>Heading</h1><p>Text</p>"
	actual := convertToGoString(convertMarkdownToHTML(convertToCString(source)))
	assert.Equal(t, expected, minifyHTML(actual))
}

func TestConvertMarkdownToHTMLWithFrontMatter(t *testing.T) {
	source := `---
key: Value
key2: Another value
---

# Heading

Text`
	actual := convertToGoString(convertMarkdownToHTML(convertToCString(source)))
	assert.True(t, strings.Contains(actual, `<pre tabindex="0" class="chroma">`))
	assert.True(t, strings.Contains(minifyHTML(actual), `<h1>Heading</h1><p>Text</p>`))
}

func TestConvertMarkdownToHTMLWithSyntaxHighlighting(t *testing.T) {
	source := "# Heading\n\nText\n\n```js\nconst print = (text) => console.log(text);\nprint(\"Hello world\");\n```" // nolint:lll
	actual := convertToGoString(convertMarkdownToHTML(convertToCString(source)))
	assert.True(t, strings.Contains(actual, `<pre tabindex="0" class="chroma">`))
}

func TestConvertMarkdownToHTMLWithMermaid(t *testing.T) {
	source := "# Diagram\n\n```mermaid\nflowchart LR\n    A --> B\n```"
	actual := convertToGoString(convertMarkdownToHTML(convertToCString(source)))
	assert.True(t, strings.Contains(actual, `<pre class="mermaid" data-glance-mermaid="1">`))
	assert.True(t, strings.Contains(actual, "flowchart LR"))
	// `>` must be HTML-escaped so the source survives until mermaid reads it
	// from the DOM as text content
	assert.True(t, strings.Contains(actual, "A --&gt; B"))
	// The mermaid block must not have been routed through chroma syntax highlighting
	assert.False(t, strings.Contains(actual, `class="chroma"`))
}

func TestConvertMarkdownToHTMLWithMermaidAndCodeBlock(t *testing.T) {
	source := "```mermaid\nflowchart LR\n    A --> B\n```\n\n```js\nconst x = 1;\n```"
	actual := convertToGoString(convertMarkdownToHTML(convertToCString(source)))
	// mermaid block bypasses chroma
	assert.True(t, strings.Contains(actual, `<pre class="mermaid" data-glance-mermaid="1">`))
	// regular code block still gets chroma syntax highlighting
	assert.True(t, strings.Contains(actual, `<pre tabindex="0" class="chroma">`))
}

func TestConvertMarkdownToHTMLWithMermaidUppercase(t *testing.T) {
	// Language matching must be case-insensitive (chroma is too)
	source := "```Mermaid\nflowchart LR\n    A --> B\n```"
	actual := convertToGoString(convertMarkdownToHTML(convertToCString(source)))
	assert.True(t, strings.Contains(actual, `data-glance-mermaid="1"`))
	assert.False(t, strings.Contains(actual, `class="chroma"`))
}

func TestConvertMarkdownToHTMLWithMermaidExtraInfoArgs(t *testing.T) {
	// Goldmark splits the info string at the first space, so extra args
	// after the language identifier must not break detection
	source := "```mermaid foo bar\nflowchart LR\n    A --> B\n```"
	actual := convertToGoString(convertMarkdownToHTML(convertToCString(source)))
	assert.True(t, strings.Contains(actual, `data-glance-mermaid="1"`))
}

func TestConvertMarkdownToHTMLWithMermaidEmpty(t *testing.T) {
	source := "```mermaid\n```"
	actual := convertToGoString(convertMarkdownToHTML(convertToCString(source)))
	// Empty blocks still emit the sentinel; mermaid will render nothing,
	// but the block must not fall back to chroma
	assert.True(t, strings.Contains(actual, `data-glance-mermaid="1"`))
	assert.False(t, strings.Contains(actual, `class="chroma"`))
}

func TestConvertMarkdownToHTMLWithMermaidHTMLEscaping(t *testing.T) {
	// Diagram syntax containing HTML-special chars in labels must survive
	// as HTML entities so mermaid reads the original via textContent
	source := "```mermaid\nflowchart LR\n    A[\"<b>label</b>\"] --> B\n```"
	actual := convertToGoString(convertMarkdownToHTML(convertToCString(source)))
	assert.True(t, strings.Contains(actual, `&lt;b&gt;label&lt;/b&gt;`))
	assert.False(t, strings.Contains(actual, `<b>label</b>`))
}

func TestConvertMarkdownToHTMLWithMermaidInBlockquote(t *testing.T) {
	// Mermaid blocks nested inside other block-level constructs must
	// still be rewritten (parent.ReplaceChild handles non-document parents)
	source := "> ```mermaid\n> flowchart LR\n>     A --> B\n> ```"
	actual := convertToGoString(convertMarkdownToHTML(convertToCString(source)))
	assert.True(t, strings.Contains(actual, `data-glance-mermaid="1"`))
}

func TestConvertMarkdownToHTMLWithLiteralMermaidPreInCode(t *testing.T) {
	// The Swift side detects mermaid blocks via the data-glance-mermaid
	// sentinel. Goldmark must NEVER emit that sentinel for content that's
	// not a real mermaid block — even when the user pastes the literal
	// HTML inside an inline-code span, a fenced code block, or an indented
	// code block.
	source := "Here is some text: `<pre class=\"mermaid\" data-glance-mermaid=\"1\">`\n\n" +
		"```html\n<pre class=\"mermaid\" data-glance-mermaid=\"1\">\n```\n\n" +
		"    <pre class=\"mermaid\" data-glance-mermaid=\"1\">\n"
	actual := convertToGoString(convertMarkdownToHTML(convertToCString(source)))
	assert.False(t, strings.Contains(actual, `<pre class="mermaid" data-glance-mermaid="1">`))
}

func TestConvertMarkdownToHTMLWithMultipleMermaidBlocks(t *testing.T) {
	// Two consecutive mermaid blocks must both be rewritten — guards
	// against a future regression where the transformer only handles
	// the first match
	source := "```mermaid\nflowchart LR\n    A --> B\n```\n\n" +
		"```mermaid\nsequenceDiagram\n    Alice->>Bob: hi\n```"
	actual := convertToGoString(convertMarkdownToHTML(convertToCString(source)))
	assert.Equal(t, 2, strings.Count(actual, `data-glance-mermaid="1"`))
}

func TestMermaidBlockOpenTagContainsSentinel(t *testing.T) {
	// The Swift-side detection in QLPlugin/Views/Previews/MarkdownPreview.swift
	// hardcodes the sentinel literal `data-glance-mermaid="1"`. Renaming it
	// in Go without updating Swift would silently break runtime detection
	// (the Swift code would compile and the Go tests would still pass
	// without this assertion). This test pins the contract.
	const sentinel = `data-glance-mermaid="1"`
	assert.True(
		t,
		strings.Contains(MermaidBlockOpenTag, sentinel),
		"MermaidBlockOpenTag must contain %q so Swift detection works",
		sentinel,
	)
}

func TestConvertNotebookToHTML(t *testing.T) {
	source := `{"cells":[{"cell_type":"code","execution_count":1,"metadata":{},"outputs":[{"name":"stdout","output_type":"stream","text":["Hello world\n"]}],"source":["print(\"Hello world\")"]}],"metadata":{"kernelspec":{"display_name":"Python 3","language":"python","name":"python3"},"language_info":{"codemirror_mode":{"name":"ipython","version":3},"file_extension":".py","mimetype":"text/x-python","name":"python","nbconvert_exporter":"python","pygments_lexer":"ipython3","version":"3.8.2"}},"nbformat":4,"nbformat_minor":4}` // nolint:lll
	actual := convertToGoString(convertNotebookToHTML(convertToCString(source)))
	actualTrimmed := strings.TrimSpace(actual)
	assert.True(t, strings.HasPrefix(actualTrimmed, `<div class="notebook">`))
	assert.True(t, strings.HasSuffix(actualTrimmed, `</div>`))
}

func TestConvertNotebookToHTMLInvalid(t *testing.T) {
	source := "This is not a valid JSON file."
	actual := convertToGoString(convertNotebookToHTML(convertToCString(source)))
	assert.True(t, strings.HasPrefix(actual, "error: "))
}
