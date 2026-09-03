// .md 파일 등에서 복사한 순수 텍스트(clipboard에 text/html이 없는 경우)를 붙여넣을 때,
// "# 제목"·"- 목록" 같은 글자를 그대로 문단에 박아 넣는 대신 실제 서식으로 렌더링한다.
// 클립보드에 text/html이 있으면(리치 텍스트 붙여넣기) 이 경로를 타지 않고 기존
// sanitizePastedHTML 파이프라인을 그대로 쓴다 — 이미 서식이 있는 걸 마크다운으로 다시
// 해석하면 오히려 원래 서식이 깨진다.

import MarkdownIt from "markdown-it";
import taskLists from "markdown-it-task-lists";
import { sanitizePastedHTML } from "./sanitize.js";

const markdownParser = new MarkdownIt({ html: false, linkify: true, breaks: false })
  .use(taskLists, { enabled: true, label: true });

// 최소 하나의 마크다운 블록 문법이 보일 때만 변환한다. 이 검사가 없으면 "안녕하세요, *잘*
// 부탁드립니다" 같은 평범한 문장의 별표까지 기울임으로 바뀌어 버려서, 마크다운을 쓸 생각이
// 없던 사용자에게는 오히려 방해가 된다.
const MARKDOWN_SIGNATURE_PATTERNS = [
  /^#{1,6}\s+\S/m, // heading
  /^[-*+]\s+\[[ xX]\]\s+\S/m, // task list
  /^[-*+]\s+\S/m, // bullet list
  /^\d+\.\s+\S/m, // ordered list
  /^>\s?\S/m, // blockquote
  /^```/m, // fenced code block
  /^\|.*\|\s*$/m, // table row
  /^(?:-{3,}|\*{3,}|_{3,})\s*$/m, // horizontal rule
  /\[[^\]\n]+\]\([^)\n]+\)/, // [text](url)
  /(\*\*|__)[^\s*_][^*_\n]*\1/, // **bold** / __bold__
];

export function looksLikeMarkdown(text) {
  return typeof text === "string" && MARKDOWN_SIGNATURE_PATTERNS.some(pattern => pattern.test(text));
}

// markdown-it-task-lists는 <li><label><input type="checkbox"> 텍스트</label></li> 형태로
// 렌더링하는데, Tiptap의 TaskItem/TaskList 확장은 <ul data-type="taskList">
// <li data-type="taskItem" data-checked="true|false"> 형태만 인식한다. sanitizePastedHTML도
// <input>은 위험 태그로 통째로 제거하므로, 그 전에 우리가 먼저 형식을 맞춰 둔다.
function convertTaskListMarkupForTiptap(html) {
  const doc = new DOMParser().parseFromString(html, "text/html");
  doc.querySelectorAll("li").forEach(li => {
    const checkbox = li.querySelector('input[type="checkbox"]');
    if (!checkbox) return;
    const checked = checkbox.checked;
    const label = checkbox.closest("label");
    checkbox.remove();
    if (label) label.replaceWith(...label.childNodes);
    li.setAttribute("data-type", "taskItem");
    li.setAttribute("data-checked", String(checked));
    li.classList.remove("task-list-item", "enabled");
    if (li.classList.length === 0) li.removeAttribute("class");
    if (li.parentElement) li.parentElement.setAttribute("data-type", "taskList");
  });
  return doc.body.innerHTML;
}

/** 마크다운처럼 보이면 정제된 HTML을, 아니면 null을 돌려준다(호출자가 기본 붙여넣기로 넘어간다). */
export function markdownTextToSanitizedHTML(text) {
  if (!looksLikeMarkdown(text)) return null;
  const rendered = markdownParser.render(text);
  const withTaskLists = convertTaskListMarkupForTiptap(rendered);
  return sanitizePastedHTML(withTaskLists);
}
