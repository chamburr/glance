(() => {
  // Transform rendered blockquotes only; code, unknown markers and source stay untouched.
  const alertNames = {NOTE:'Note', TIP:'Tip', IMPORTANT:'Important', WARNING:'Warning', CAUTION:'Caution'};
  document.querySelectorAll('.markdown-body blockquote').forEach(quote => {
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
  const style = document.createElement('style');
  style.textContent = `.markdown-alert{border-left:4px solid #0969da;padding:8px 16px;margin:16px 0}.markdown-alert-title{font-weight:600}.markdown-alert-tip{border-color:#1a7f37}.markdown-alert-important{border-color:#8250df}.markdown-alert-warning{border-color:#9a6700}.markdown-alert-caution{border-color:#cf222e}`;
  document.head.append(style);
})();
