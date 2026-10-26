(() => {
  if (typeof renderMathInElement === 'function') {
    renderMathInElement(document.querySelector('.markdown-body'), {
      delimiters: [{left:'$$',right:'$$',display:true},{left:'\\[',right:'\\]',display:true},
        {left:'\\(',right:'\\)',display:false},{left:'$',right:'$',display:false}],
      throwOnError:false, trust:false, maxExpand:1000, maxSize:50
    });
  }
})();
