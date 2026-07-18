// 붙여넣은 HTML에서 위험한 요소를 제거한다 (스펙 6절/22절).
// script, iframe, object, embed, style, link, meta, base, form 등을 통째로 제거하고
// 남은 요소에서도 on* 이벤트 핸들러 속성과 javascript:/data:text/html 스킴을 제거한다.

const BLOCKED_TAGS = new Set([
  "SCRIPT", "IFRAME", "OBJECT", "EMBED", "STYLE", "LINK", "META", "BASE",
  "FORM", "INPUT", "BUTTON", "TEXTAREA", "SELECT", "SVG", "MATH", "APPLET",
  "AUDIO", "VIDEO", "SOURCE", "TRACK", "NOSCRIPT",
]);

const DANGEROUS_URL_SCHEME = /^\s*(javascript|vbscript):/i;
// data: 자체를 통째로 막으면 이미지를 붙여넣기(handlePaste)가 아니라 일반 HTML 붙여넣기
// 경로로 다시 들어오는 경우(예: 이미 삽입된 이미지를 복사해서 같은 문서/다른 노트에 다시
// 붙여넣기)에 우리 자신이 base64로 저장한 이미지까지 통째로 걸러져서 조용히 사라졌다.
// data:image/*는 브라우저가 스크립트로 해석하지 않는 순수 바이너리라 안전하다 — 실행 가능한
// data:text/html, data:application/* 같은 스킴만 계속 막는다.
const DANGEROUS_DATA_URI = /^\s*data:(?!image\/)/i;

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
      if ((name === "href" || name === "src" || name === "xlink:href") &&
          (DANGEROUS_URL_SCHEME.test(attr.value) || DANGEROUS_DATA_URI.test(attr.value))) {
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
