// 붙여넣은 HTML에서 위험한 요소를 제거한다 (스펙 6절/22절).
// script, iframe, object, embed, style, link, meta, base, form 등을 통째로 제거하고
// 남은 요소에서도 on* 이벤트 핸들러 속성과 javascript:/data:text/html 스킴을 제거한다.

const BLOCKED_TAGS = new Set([
  "SCRIPT", "IFRAME", "OBJECT", "EMBED", "STYLE", "LINK", "META", "BASE",
  "FORM", "INPUT", "BUTTON", "TEXTAREA", "SELECT", "SVG", "MATH", "APPLET",
  "AUDIO", "VIDEO", "SOURCE", "TRACK", "NOSCRIPT",
]);

const DANGEROUS_URL_SCHEME = /^\s*(javascript|data|vbscript):/i;

function sanitizeElement(element) {
  const toRemove = [];

  for (const node of Array.from(element.querySelectorAll("*"))) {
    if (BLOCKED_TAGS.has(node.tagName)) {
      toRemove.push(node);
      continue;
    }
    for (const attr of Array.from(node.attributes)) {
      const name = attr.name.toLowerCase();
      if (name.startsWith("on")) {
        node.removeAttribute(attr.name);
        continue;
      }
      if ((name === "href" || name === "src" || name === "xlink:href") && DANGEROUS_URL_SCHEME.test(attr.value)) {
        node.removeAttribute(attr.name);
      }
      if (name === "style") {
        // CSS expression()/url(javascript:) 같은 레거시 벡터를 막는다.
        if (/expression\s*\(|javascript:/i.test(attr.value)) {
          node.removeAttribute(attr.name);
        }
      }
    }
  }

  toRemove.forEach(node => node.remove());
  return element;
}

/** Tiptap의 editorProps.transformPastedHTML 훅에서 호출한다. */
export function sanitizePastedHTML(html) {
  const parser = new DOMParser();
  const doc = parser.parseFromString(html, "text/html");
  sanitizeElement(doc.body);
  return doc.body.innerHTML;
}
