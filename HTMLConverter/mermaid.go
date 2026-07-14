package main

import (
	"strings"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/parser"
	"github.com/yuin/goldmark/renderer"
	"github.com/yuin/goldmark/text"
	"github.com/yuin/goldmark/util"
)

const mermaidLanguage = "mermaid"

// MermaidBlockOpenTag is the opening tag emitted for mermaid diagrams. Swift
// uses the `data-glance-mermaid` attribute (a sentinel users cannot forge via
// markdown) to decide whether to inject the mermaid runtime.
const MermaidBlockOpenTag = `<pre class="mermaid" data-glance-mermaid="1">`

// KindMermaidBlock is the NodeKind for mermaid diagram blocks.
var KindMermaidBlock = ast.NewNodeKind("MermaidBlock")

// MermaidBlock represents a fenced code block whose info string is `mermaid`.
// It is rendered as a `<pre class="mermaid">` element so the client-side
// mermaid runtime can replace it with an SVG diagram.
type MermaidBlock struct {
	ast.BaseBlock
}

func (n *MermaidBlock) Kind() ast.NodeKind {
	return KindMermaidBlock
}

// IsRaw matches the semantics of FencedCodeBlock: the contents are raw text
// that must not be inline-parsed.
func (n *MermaidBlock) IsRaw() bool {
	return true
}

func (n *MermaidBlock) Dump(source []byte, level int) {
	ast.DumpHelper(n, source, level, nil, nil)
}

// mermaidTransformer rewrites FencedCodeBlock nodes whose language is `mermaid`
// (case-insensitive) into MermaidBlock nodes, so they bypass syntax highlighting.
type mermaidTransformer struct{}

func (t *mermaidTransformer) Transform(doc *ast.Document, reader text.Reader, _ parser.Context) {
	source := reader.Source()
	var targets []*ast.FencedCodeBlock
	_ = ast.Walk(doc, func(n ast.Node, entering bool) (ast.WalkStatus, error) {
		if !entering {
			return ast.WalkContinue, nil
		}
		if cb, ok := n.(*ast.FencedCodeBlock); ok {
			if strings.EqualFold(string(cb.Language(source)), mermaidLanguage) {
				targets = append(targets, cb)
			}
			// Fenced code blocks have no relevant block-level descendants
			return ast.WalkSkipChildren, nil
		}
		return ast.WalkContinue, nil
	})

	for _, cb := range targets {
		replacement := &MermaidBlock{}
		replacement.SetLines(cb.Lines())
		replacement.SetBlankPreviousLines(cb.HasBlankPreviousLines())
		parent := cb.Parent()
		parent.ReplaceChild(parent, cb, replacement)
	}
}

// mermaidRenderer renders MermaidBlock nodes as a sentinel-marked `<pre>`.
type mermaidRenderer struct{}

func (r *mermaidRenderer) RegisterFuncs(reg renderer.NodeRendererFuncRegisterer) {
	reg.Register(KindMermaidBlock, r.render)
}

func (r *mermaidRenderer) render(
	w util.BufWriter,
	source []byte,
	n ast.Node,
	entering bool,
) (ast.WalkStatus, error) {
	if !entering {
		return ast.WalkContinue, nil
	}
	block, ok := n.(*MermaidBlock)
	if !ok {
		return ast.WalkStop, nil
	}
	_, _ = w.WriteString(MermaidBlockOpenTag)
	lines := block.Lines()
	for i := range lines.Len() {
		segment := lines.At(i)
		_, _ = w.Write(util.EscapeHTML(segment.Value(source)))
	}
	_, _ = w.WriteString("</pre>\n")
	return ast.WalkContinue, nil
}

type mermaidExtension struct{}

// Mermaid is a goldmark extension that handles ```mermaid``` fenced code blocks.
var Mermaid goldmark.Extender = &mermaidExtension{}

func (e *mermaidExtension) Extend(md goldmark.Markdown) {
	// Transformer priority is uncontested in practice (no other extension
	// touches FencedCodeBlock at parse time); 100 is a low-but-not-extreme
	// slot. The renderer is the only one registered for KindMermaidBlock,
	// so its priority is cosmetic.
	md.Parser().AddOptions(parser.WithASTTransformers(
		util.Prioritized(&mermaidTransformer{}, 100),
	))
	md.Renderer().AddOptions(renderer.WithNodeRenderers(
		util.Prioritized(&mermaidRenderer{}, 500),
	))
}
