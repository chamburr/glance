(async () => {
  window.glanceReady = false;
  // Transform rendered blockquotes only; code, unknown markers and source stay untouched.
  const alertNames = {NOTE:'Note', TIP:'Tip', IMPORTANT:'Important', WARNING:'Warning', CAUTION:'Caution'};
  document.querySelectorAll('main blockquote').forEach(quote => {
    const paragraph = quote.firstElementChild;
    const text = paragraph?.firstChild;
    if (paragraph?.tagName !== 'P' || text?.nodeType !== Node.TEXT_NODE) return;
    const match = text.textContent.match(/^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\](?:\r?\n|$)/);
    if (!match) return;
    const kind = match[1].toLowerCase();
    quote.classList.add('markdown-alert', 'markdown-alert-' + kind);
    quote.setAttribute('role', 'note');
    const title = document.createElement('p');
    title.className = 'markdown-alert-title'; title.textContent = alertNames[match[1]];
    quote.prepend(title); text.textContent = text.textContent.slice(match[0].length);
    if (!paragraph.textContent.trim() && !paragraph.querySelector('img')) paragraph.remove();
  });
  const calloutStyle = document.createElement('style');
  calloutStyle.textContent = `.markdown-alert{border-left:4px solid #0969da;padding:8px 16px;margin:16px 0}
    .markdown-alert-title{font-weight:600}.markdown-alert-tip{border-color:#1a7f37}
    .markdown-alert-important{border-color:#8250df}.markdown-alert-warning{border-color:#9a6700}
    .markdown-alert-caution{border-color:#cf222e}.glance-diagram-controls{display:flex;gap:6px;justify-content:center;margin:6px}
    .glance-diagram-controls button{font:inherit;color:inherit;background:transparent;border:1px solid currentColor;border-radius:5px;padding:2px 8px}`;
  document.head.append(calloutStyle);
  if (typeof renderMathInElement === 'function') {
    renderMathInElement(document.querySelector('main'), {
      delimiters: [{left:'$$',right:'$$',display:true},{left:'\\[',right:'\\]',display:true},
        {left:'\\(',right:'\\)',display:false},{left:'$',right:'$',display:false}],
      throwOnError:false, trust:false, maxExpand:1000, maxSize:50
    });
  }
  if (typeof mermaid !== 'undefined') {
    const appearance = matchMedia('(prefers-color-scheme: dark)');
    const diagrams = Array.from(document.querySelectorAll('code.language-mermaid')).slice(0,20)
      .filter(code => code.textContent.length <= 50000)
      .map(code => ({node:code.parentElement, source:code.textContent}));
    diagrams.forEach(diagram => {
      diagram.scale = 1;
      const controls = document.createElement('div');
      controls.className = 'glance-diagram-controls';
      const applyScale = () => {
        const svg = diagram.node.querySelector('svg');
        if (!svg) return;
        const width = svg.viewBox.baseVal.width;
        if (width > 0) {
          svg.style.width = (width * diagram.scale) + 'px';
          svg.style.maxWidth = diagram.scale === 1 ? '100%' : 'none';
        }
        diagram.node.style.overflow = 'auto';
      };
      diagram.applyScale = applyScale;
      for (const [label, title, change] of [['−', 'Zoom out diagram', -0.25], ['Reset', 'Reset diagram zoom', 0], ['+', 'Zoom in diagram', 0.25]]) {
        const button = document.createElement('button');
        button.type = 'button'; button.textContent = label; button.setAttribute('aria-label', title);
        button.addEventListener('click', () => {
          diagram.scale = change === 0 ? 1 : Math.min(4, Math.max(0.25, diagram.scale + change));
          applyScale();
        });
        controls.append(button);
      }
      diagram.node.after(controls);
    });
    // Serialize redraws so rapid appearance changes cannot race Mermaid's shared renderer.
    let queue = Promise.resolve();
    const redraw = () => {
      queue = queue.then(async () => {
        window.glanceReady = false;
        mermaid.initialize({startOnLoad:false, securityLevel:'strict',
          secure:['secure','securityLevel','startOnLoad','maxTextSize','maxEdges'],
          theme:appearance.matches ? 'dark' : 'default', maxTextSize:50000, maxEdges:500,
          flowchart:{htmlLabels:false}});
        for (const diagram of diagrams) {
          const {node, source} = diagram;
          node.className = 'mermaid'; node.textContent = source;
          node.removeAttribute('data-processed');
          try { await mermaid.run({nodes:[node], suppressErrors:true}); diagram.applyScale(); }
          catch (_) { node.textContent = source; }
        }
        window.glanceReady = true;
        document.dispatchEvent(new Event('glance-ready'));
      });
      return queue;
    };
    appearance.addEventListener('change', () => { redraw(); });
    await redraw();
  } else {
    window.glanceReady = true;
    document.dispatchEvent(new Event('glance-ready'));
  }
})();
