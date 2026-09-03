import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import Underline from "@tiptap/extension-underline";
import Highlight from "@tiptap/extension-highlight";
import TextStyle from "@tiptap/extension-text-style";
import Color from "@tiptap/extension-color";
import FontFamily from "@tiptap/extension-font-family";
import Subscript from "@tiptap/extension-subscript";
import Superscript from "@tiptap/extension-superscript";
import LinkExtension from "@tiptap/extension-link";
import Table from "@tiptap/extension-table";
import TableRow from "@tiptap/extension-table-row";
import TableHeader from "@tiptap/extension-table-header";
import TableCell from "@tiptap/extension-table-cell";
import TaskList from "@tiptap/extension-task-list";
import TaskItem from "@tiptap/extension-task-item";
import CodeBlockLowlight from "@tiptap/extension-code-block-lowlight";

import { lowlight } from "./languages.js";
import { sanitizePastedHTML } from "./sanitize.js";
import { markdownTextToSanitizedHTML } from "./markdownPaste.js";
import { FontSize, Details, DetailsSummary, DetailsContent, FileAttachment, ArrowTypography, ResizableImage } from "./extensions.js";

// ---------------------------------------------------------------------------
// Swift 브리지: 허용된 메시지 이름만 window.webkit.messageHandlers로 보낸다.
// ---------------------------------------------------------------------------
function postToNative(type, payload) {
  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.notepadXBridge) {
    window.webkit.messageHandlers.notepadXBridge.postMessage({ type, payload });
  }
}

// 외부 링크는 절대 WKWebView 안에서 로드하지 않고 항상 네이티브로 위임한다.
document.addEventListener("click", event => {
  const anchor = event.target && event.target.closest ? event.target.closest("a[href]") : null;
  if (anchor) {
    event.preventDefault();
    postToNative("openExternalLink", { url: anchor.getAttribute("href") });
  }
}, true);

const ACTIVE_MARKS = ["bold", "italic", "underline", "strike", "code", "subscript", "superscript"];
const ACTIVE_BLOCKS = [
  "paragraph", "heading", "bulletList", "orderedList", "taskList",
  "blockquote", "codeBlock", "table", "details", "horizontalRule",
];

// 이미지 붙여넣기/드래그앤드롭. 앱이 완전히 오프라인이고 문서(JSON) 하나가 곧 노트 전체이므로,
// 별도 첨부파일 저장소/URL 스킴 없이 base64 data URI로 문서 안에 그대로 끼워 넣는다 — 그래야
// 내보내기·복사·복원까지 항상 문서 JSON만 옮기면 이미지도 같이 따라간다. index.html의
// CSP(img-src 'self' data:)도 이 방식을 전제로 이미 열어 두었다.
const MAX_PASTED_IMAGE_BYTES = 10 * 1024 * 1024;

// 큰 사진(요즘 카메라 사진은 흔히 몇 MB)을 원본 바이트 그대로 문서 JSON에 박아 넣으면, 편집할
// 때마다(scheduleDocChanged) 그 몇 MB짜리 base64 문자열 전체를 WKWebView의 JS→Swift
// postMessage 브리지로 매번 다시 보내야 한다. WKScriptMessageHandler는 이런 대용량 단일
// 문자열 페이로드 직렬화에 매우 취약해서(WebContent 프로세스가 그동안 멈춘 것처럼 보임),
// 사진을 붙여넣거나 끌어놓는 순간 앱 전체가 다운된 것처럼 멈추는 원인이었다.
// 화면 표시 크기(픽셀 해상도)는 그대로 유지하되(사용자가 원본 화질을 기대하므로), 이 임계값을
// 넘는 파일만 canvas로 JPEG 재인코딩해서 전송되는 바이트 수 자체를 줄인다.
const REENCODE_THRESHOLD_BYTES = 1.5 * 1024 * 1024;
const REENCODE_JPEG_QUALITY = 0.82;

function loadImageElement(dataUrl) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error("이미지를 디코딩할 수 없습니다."));
    img.src = dataUrl;
  });
}

async function reencodeIfLarge(dataUrl, byteSize) {
  if (byteSize <= REENCODE_THRESHOLD_BYTES) return dataUrl;
  const img = await loadImageElement(dataUrl);
  const canvas = document.createElement("canvas");
  canvas.width = img.naturalWidth;
  canvas.height = img.naturalHeight;
  const ctx = canvas.getContext("2d");
  // JPEG는 알파 채널이 없어서, 투명 배경이 있는 원본(PNG 스크린샷 등)을 그대로 그리면
  // 캔버스 기본값인 검정 배경이 비쳐 보인다 — 흰 배경을 먼저 깔아 둔다.
  ctx.fillStyle = "#ffffff";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(img, 0, 0);
  return canvas.toDataURL("image/jpeg", REENCODE_JPEG_QUALITY);
}

/// pos가 주어지면 그 위치에 삽입한다(드래그앤드롭이 놓인 지점) — 없으면 현재 커서 위치에
/// 삽입한다(붙여넣기).
function insertImageFiles(files, pos) {
  const imageFiles = Array.from(files).filter(file => file.type.startsWith("image/"));
  if (imageFiles.length === 0) return false;
  imageFiles.forEach(file => {
    if (file.size > MAX_PASTED_IMAGE_BYTES) {
      postToNative("error", {
        message: `이미지가 너무 큽니다 (${Math.round(file.size / 1024 / 1024)}MB). 10MB 이하 이미지만 붙여넣을 수 있습니다.`,
      });
      return;
    }
    const reader = new FileReader();
    reader.onload = async () => {
      if (typeof reader.result !== "string") return;
      let src = reader.result;
      try {
        src = await reencodeIfLarge(src, file.size);
      } catch {
        postToNative("error", { message: "이미지를 처리하는 중 오류가 발생했습니다." });
        return;
      }
      const chain = editor.chain().focus();
      if (typeof pos === "number") chain.setTextSelection(pos);
      chain.setImage({ src }).run();
    };
    reader.onerror = () => {
      postToNative("error", { message: "이미지를 붙여넣는 중 오류가 발생했습니다." });
    };
    reader.readAsDataURL(file);
  });
  return true;
}

// 이미지가 아닌 파일(문서·PDF·압축파일 등) 붙여넣기/드래그앤드롭. 이미지처럼 base64로 문서
// JSON에 통째로 담지 않는다 — 그러면 노트마다 원본 파일 전체를 SQLite에 들고 있게 되고,
// scheduleDocChanged가 편집할 때마다 그 바이트를 다시 JS→Swift 브리지로 보내야 해서 위
// MAX_PASTED_IMAGE_BYTES 주석에 적힌 것과 같은 멈춤 문제가 재발한다. 대신 attachmentId만
// 문서에 남기고, 실제 바이트는 saveAttachment 메시지로 Swift에 딱 한 번만(편집할 때마다가
// 아니라) 보내 AttachmentStorage.swift가 앱 전용 Attachments 폴더에 파일 그대로(Finder에서
// 아이콘으로 열어볼 수 있게) 저장하게 한다 — 그래서 이미지의 10MB 캡보다 여유 있게(한글
// 문서·PDF 같은 큰 첨부도 담을 수 있게) 20MB까지 허용해도, 매번 재전송되는 게 아니라
// 안전하다.
const MAX_ATTACHMENT_BYTES = 20 * 1024 * 1024;

function generateAttachmentId() {
  if (window.crypto && typeof window.crypto.randomUUID === "function") return window.crypto.randomUUID();
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function insertFileAttachments(files, pos) {
  const otherFiles = Array.from(files).filter(file => !file.type.startsWith("image/"));
  if (otherFiles.length === 0) return false;
  otherFiles.forEach(file => {
    if (file.size > MAX_ATTACHMENT_BYTES) {
      const capMB = Math.round(MAX_ATTACHMENT_BYTES / 1024 / 1024);
      postToNative("error", {
        message: `파일이 너무 큽니다 (${Math.round(file.size / 1024 / 1024)}MB). ${capMB}MB 이하 파일만 첨부할 수 있습니다.`,
      });
      return;
    }
    const attachmentId = generateAttachmentId();
    const reader = new FileReader();
    reader.onload = () => {
      if (typeof reader.result !== "string") return;
      const commaIndex = reader.result.indexOf(",");
      const base64Data = commaIndex >= 0 ? reader.result.slice(commaIndex + 1) : "";
      const mimeType = file.type || "application/octet-stream";
      const chain = editor.chain().focus();
      if (typeof pos === "number") chain.setTextSelection(pos);
      chain.insertContent({
        type: "fileAttachment",
        attrs: { attachmentId, fileName: file.name, byteSize: file.size, mimeType },
      }).run();
      postToNative("saveAttachment", { attachmentId, fileName: file.name, mimeType, base64Data });
    };
    reader.onerror = () => {
      postToNative("error", { message: "파일을 첨부하는 중 오류가 발생했습니다." });
    };
    reader.readAsDataURL(file);
  });
  return true;
}

let updateTimer = null;
function scheduleDocChanged() {
  if (updateTimer) clearTimeout(updateTimer);
  updateTimer = setTimeout(() => {
    updateTimer = null;
    const json = editor.getJSON();
    const plainText = editor.getText({ blockSeparator: "\n" });
    postToNative("docChanged", {
      schemaVersion: 1,
      type: "doc",
      content: json.content || [],
      plainText,
    });
    postHeadings();
  }, 150);
}

// 왼쪽 문서 개요 패널(DocumentOutlineView.swift)용. pos는 ProseMirror 문서 안의 위치이고,
// Swift는 이 값을 해석하지 않고 scrollToHeading 커맨드의 인자로 그대로 되돌려 보낸다.
function postHeadings() {
  const headings = [];
  editor.state.doc.descendants((node, pos) => {
    if (node.type.name === "heading") {
      headings.push({ pos, level: node.attrs.level, text: node.textContent });
    }
    return true;
  });
  postToNative("headingsChanged", { headings });
}

// Tab 처리 직전에 호출해서, 아직 ProseMirror 자체 selectionchange 동기화가 안 끝났을 수
// 있는 상황에서도 실제 브라우저 선택을 기준으로 동작하게 한다(위 handleKeyDown 주석 참고).
// ProseMirror의 EditorView는 document의 'selectionchange'에 자체 리스너를 붙여 두고 있고,
// 그 핸들러(DOMObserver.onSelectionChange → flush)가 DOM 선택을 view.state.selection으로
// 정확히 반영하는 로직을 이미 갖고 있다(빈 선택/여러 노드에 걸친 범위 선택 등 다양한 경우를
// 다 다룬다). 그 로직을 우리가 posAtDOM으로 직접 재구현하면 컨테이너 경계 같은 예외 케이스를
// 놓치기 쉬우므로, 대신 그 이벤트를 지금 당장 한 번 더 발생시켜 ProseMirror 자신의 동기화를
// 강제로(비동기 타이밍을 기다리지 않고) 실행시킨다.
function syncSelectionFromBrowser() {
  document.dispatchEvent(new Event("selectionchange"));
}

function currentBlockType() {
  for (const type of ACTIVE_BLOCKS) {
    if (editor.isActive(type)) return type;
  }
  return "paragraph";
}

function postSelection() {
  const { from, to, empty } = editor.state.selection;
  postToNative("selectionChanged", {
    from,
    to,
    empty,
    // Phase 7 LLM 패널이 "선택 영역만 보내기"를 하려면 선택된 실제 텍스트가 있어야 한다.
    selectedText: empty ? "" : editor.state.doc.textBetween(from, to, "\n"),
    activeMarks: ACTIVE_MARKS.filter(mark => editor.isActive(mark)),
    activeBlockType: currentBlockType(),
    headingLevel: editor.getAttributes("heading").level || null,
    codeBlockLanguage: editor.getAttributes("codeBlock").language || null,
    linkHref: editor.getAttributes("link").href || null,
    textColor: editor.getAttributes("textStyle").color || null,
    fontSize: editor.getAttributes("textStyle").fontSize || null,
    fontFamily: editor.getAttributes("textStyle").fontFamily || null,
  });
}

const extensions = [
  StarterKit.configure({ codeBlock: false }),
  TextStyle,
  Color,
  FontFamily,
  FontSize,
  Underline,
  Highlight.configure({ multicolor: true }),
  Subscript,
  Superscript,
  LinkExtension.configure({ openOnClick: false, autolink: true, linkOnPaste: true }),
  Table.configure({ resizable: true }),
  TableRow,
  TableHeader,
  TableCell,
  TaskList,
  TaskItem.configure({ nested: true }),
  CodeBlockLowlight.configure({ lowlight, defaultLanguage: "plaintext" }),
  ResizableImage,
  Details,
  DetailsSummary,
  DetailsContent,
  FileAttachment.configure({
    onOpenAttachment: (attachmentId, fileName) => postToNative("openAttachment", { attachmentId, fileName }),
  }),
  ArrowTypography,
];

const editor = new Editor({
  element: document.querySelector("#editor-root"),
  extensions,
  content: { type: "doc", content: [{ type: "paragraph" }] },
  autofocus: false,
  editorProps: {
    transformPastedHTML: sanitizePastedHTML,
    handlePaste(_view, event) {
      const files = event.clipboardData && event.clipboardData.files;
      if (files && files.length > 0) {
        if (insertImageFiles(files)) {
          event.preventDefault();
          return true;
        }
        if (insertFileAttachments(files)) {
          event.preventDefault();
          return true;
        }
      }
      // 클립보드에 text/html이 있으면 이미 서식이 있는 붙여넣기(리치 텍스트, 웹페이지 등)이므로
      // transformPastedHTML(sanitizePastedHTML) 경로를 그대로 타게 둔다. text/html이 없을
      // 때만(.md 파일·터미널·plain 텍스트 에디터에서 복사한 경우 등) 순수 텍스트를 마크다운으로
      // 해석해 본다.
      const clipboardData = event.clipboardData;
      const hasHTML = !!clipboardData && Array.from(clipboardData.types || []).includes("text/html");
      const plainText = clipboardData ? clipboardData.getData("text/plain") : "";
      if (!hasHTML && plainText) {
        const html = markdownTextToSanitizedHTML(plainText);
        if (html) {
          editor.chain().focus().insertContent(html, { parseOptions: { preserveWhitespace: false } }).run();
          event.preventDefault();
          return true;
        }
      }
      return false;
    },
    handleDrop(view, event) {
      const files = event.dataTransfer && event.dataTransfer.files;
      if (!files || files.length === 0) return false;
      const coords = view.posAtCoords({ left: event.clientX, top: event.clientY });
      const pos = coords ? coords.pos : undefined;
      if (insertImageFiles(files, pos)) {
        event.preventDefault();
        return true;
      }
      if (insertFileAttachments(files, pos)) {
        event.preventDefault();
        return true;
      }
      return false;
    },
    handleClickOn(_view, _pos, _node, _nodePos, event) {
      const target = event.target && event.target.closest ? event.target.closest("a[href]") : null;
      if (target) {
        event.preventDefault();
        postToNative("openExternalLink", { url: target.getAttribute("href") });
        return true;
      }
      return false;
    },
    // ListItem/TaskItem 확장의 기본 Tab 키맵(sinkListItem)은 선택 범위가 들여쓸 수 없는
    // 모양이면(예: 목록의 첫 항목이라 옮겨 붙일 이전 형제가 없는 경우) 커맨드가 실패로
    // 끝나고, ProseMirror는 그 키다운을 "처리 안 됨"으로 보고 그대로 흘려보낸다. 그러면
    // WKWebView가 표준 포커스 이동으로 받아들여서 편집기 밖(예: 검색창)으로 포커스가
    // 튀어버린다 — "입력 중엔 되는데 입력 끝나고(드래그 선택 상태)는 검색창으로 가버린다"는
    // 버그가 이래서 생겼다. 여기서 Tab을 직접 가로채 항상 preventDefault해서, 들여쓰기가
    // 실제로 안 먹는 경우에도 최소한 포커스는 편집기 안에 그대로 남게 한다.
    handleKeyDown(_view, event) {
      if (event.key !== "Tab") return false;
      event.preventDefault();
      // ProseMirror는 브라우저의 selectionchange를 통해 자신의 선택 상태를 DOM과 동기화하는데,
      // 이 이벤트는 WKWebView에서 비동기로(약간의 지연을 두고) 발생할 수 있다. 그래서 마우스로
      // 여러 줄을 드래그해 선택을 막 끝낸 직후 곧바로 Tab을 누르면, 아직 동기화되지 않은 이전
      // 선택 기준으로 들여쓰기가 계산되어 아무 일도 안 일어나거나 엉뚱한 항목이 들여써질 수
      // 있다. Tab을 처리하기 직전에 실제 브라우저 선택을 직접 읽어 강제로 반영해서, 항상
      // 사용자가 마지막으로 만든 선택 기준으로 동작하게 한다.
      syncSelectionFromBrowser();
      if (event.shiftKey) {
        COMMANDS.outdent();
      } else {
        COMMANDS.indent();
      }
      return true;
    },
  },
  onCreate() {
    postToNative("ready", {});
  },
  onUpdate() {
    scheduleDocChanged();
  },
  onSelectionUpdate() {
    postSelection();
  },
});

// ---------------------------------------------------------------------------
// 네이티브 → JS 커맨드 테이블. Swift는 이름과 JSON 인자만 넘기고,
// 여기 등록되지 않은 이름은 조용히 무시하지 않고 error 메시지로 되돌려 보낸다.
// ---------------------------------------------------------------------------
const COMMANDS = {
  toggleBold: () => editor.chain().focus().toggleBold().run(),
  toggleItalic: () => editor.chain().focus().toggleItalic().run(),
  toggleUnderline: () => editor.chain().focus().toggleUnderline().run(),
  toggleStrike: () => editor.chain().focus().toggleStrike().run(),
  toggleSubscript: () => editor.chain().focus().toggleSubscript().run(),
  toggleSuperscript: () => editor.chain().focus().toggleSuperscript().run(),
  toggleInlineCode: () => editor.chain().focus().toggleCode().run(),
  setParagraph: () => editor.chain().focus().setParagraph().run(),
  setHeading: args => editor.chain().focus().toggleHeading({ level: (args && args.level) || 1 }).run(),
  toggleBulletList: () => editor.chain().focus().toggleBulletList().run(),
  toggleOrderedList: () => editor.chain().focus().toggleOrderedList().run(),
  toggleTaskList: () => editor.chain().focus().toggleTaskList().run(),
  toggleBlockquote: () => editor.chain().focus().toggleBlockquote().run(),
  toggleCodeBlock: args => editor.chain().focus().toggleCodeBlock({ language: (args && args.language) || "plaintext" }).run(),
  setCodeBlockLanguage: args => editor.chain().focus().updateAttributes("codeBlock", { language: (args && args.language) || "plaintext" }).run(),
  setHorizontalRule: () => editor.chain().focus().setHorizontalRule().run(),
  insertDetails: () => editor.chain().focus().insertDetails().run(),
  insertTable: args => editor.chain().focus().insertTable({
    rows: (args && args.rows) || 3,
    cols: (args && args.cols) || 3,
    withHeaderRow: !(args && args.withHeaderRow === false),
  }).run(),
  addColumnBefore: () => editor.chain().focus().addColumnBefore().run(),
  addColumnAfter: () => editor.chain().focus().addColumnAfter().run(),
  deleteColumn: () => editor.chain().focus().deleteColumn().run(),
  addRowBefore: () => editor.chain().focus().addRowBefore().run(),
  addRowAfter: () => editor.chain().focus().addRowAfter().run(),
  deleteRow: () => editor.chain().focus().deleteRow().run(),
  deleteTable: () => editor.chain().focus().deleteTable().run(),
  mergeCells: () => editor.chain().focus().mergeCells().run(),
  splitCell: () => editor.chain().focus().splitCell().run(),
  toggleHeaderRow: () => editor.chain().focus().toggleHeaderRow().run(),
  setLink: args => {
    const href = args && args.href;
    if (!href) return false;
    return editor.chain().focus().extendMarkRange("link").setLink({ href }).run();
  },
  unsetLink: () => editor.chain().focus().unsetLink().run(),
  setTextColor: args => editor.chain().focus().setColor((args && args.color) || "#000000").run(),
  unsetTextColor: () => editor.chain().focus().unsetColor().run(),
  setHighlight: args => editor.chain().focus().toggleHighlight({ color: (args && args.color) || "#fff59d" }).run(),
  unsetHighlight: () => editor.chain().focus().unsetHighlight().run(),
  // size는 유효한 CSS 길이 문자열이면 무엇이든 그대로 쓰인다("20pt"·"16px" 등) — pt로
  // 통일해서 쓰는 이유는 EditorToolbar.swift의 5~125pt 프리셋/직접 입력과 맞추기 위해서다.
  setFontSize: args => editor.chain().focus().setFontSize((args && args.size) || "16pt").run(),
  unsetFontSize: () => editor.chain().focus().unsetFontSize().run(),
  setFontFamily: args => editor.chain().focus().setFontFamily((args && args.family) || "inherit").run(),
  unsetFontFamily: () => editor.chain().focus().unsetFontFamily().run(),
  indent: () => editor.chain().focus().sinkListItem("listItem").run() || editor.chain().focus().sinkListItem("taskItem").run(),
  outdent: () => editor.chain().focus().liftListItem("listItem").run() || editor.chain().focus().liftListItem("taskItem").run(),
  clearFormatting: () => editor.chain().focus().unsetAllMarks().clearNodes().run(),
  undo: () => editor.chain().focus().undo().run(),
  redo: () => editor.chain().focus().redo().run(),
  selectAll: () => editor.chain().focus().selectAll().run(),
  // Phase 7: LLM 응답을 문서에 반영할 때 쓴다. 순수 텍스트를 문단 단위로 쪼개 삽입한다 —
  // LLM이 마크다운을 돌려줘도 서식 있는 노드로 파싱하지 않고 평문 그대로 넣는다(예상 밖의
  // 마크업이 섞여 들어오는 것을 막기 위함이며, 필요하면 사용자가 직접 다시 서식을 입힌다).
  replaceSelectionWithText: args =>
    editor.chain().focus().deleteSelection().insertContent(textToParagraphNodes((args && args.text) || "")).run(),
  insertTextBelowSelection: args => {
    const { to } = editor.state.selection;
    return editor.chain().focus().setTextSelection(to).insertContent(textToParagraphNodes((args && args.text) || "")).run();
  },
  insertTextAtEnd: args => {
    const endPos = editor.state.doc.content.size;
    return editor.chain().focus().setTextSelection(endPos).insertContent(textToParagraphNodes((args && args.text) || "")).run();
  },
  // 왼쪽 개요 패널에서 제목을 클릭했을 때. pos는 postHeadings가 보냈던 값을 그대로
  // 돌려받은 것이라, 그 사이 문서가 바뀌었다면(다른 곳에서 텍스트를 지웠다든지) 범위를
  // 벗어날 수 있으므로 문서 크기로 clamp한다.
  scrollToHeading: args => {
    const pos = args && typeof args.pos === "number" ? args.pos : null;
    if (pos === null) return false;
    const clamped = Math.max(0, Math.min(pos, editor.state.doc.content.size));
    return editor.chain().focus().setTextSelection(clamped).scrollIntoView().run();
  },
};

function textToParagraphNodes(text) {
  const lines = String(text).split("\n");
  return lines.map(line => ({
    type: "paragraph",
    content: line ? [{ type: "text", text: line }] : [],
  }));
}

// Swift는 evaluateJavaScript로 JSON을 그대로 JS 객체 리터럴로 인라인하여 호출하므로
// (JSON 문법은 JS 리터럴 문법의 부분집합이다) 여기서는 문자열 파싱 없이 객체를 바로 받는다.
function loadDocument(doc) {
  try {
    const content = doc && Array.isArray(doc.content) ? doc.content : [{ type: "paragraph" }];
    // 세 번째 인자 false: setContent가 onUpdate를 다시 발생시켜
    // 방금 불러온 문서를 즉시 "변경됨"으로 재저장하는 루프를 막는다. onUpdate가 안 도므로
    // 개요 패널 갱신(postHeadings)은 따로 호출해야 한다.
    editor.commands.setContent({ type: "doc", content }, false);
    postHeadings();
  } catch (error) {
    postToNative("error", { message: `loadDocument failed: ${String(error)}` });
  }
}

window.NotepadXBridge = {
  loadDocument,
  applyCommand(name, args) {
    const fn = COMMANDS[name];
    if (!fn) {
      postToNative("error", { message: `Unknown command: ${name}` });
      return;
    }
    try {
      fn(args || null);
    } catch (error) {
      postToNative("error", { message: `applyCommand(${name}) failed: ${String(error)}` });
    }
  },
  setTheme(theme) {
    document.documentElement.dataset.theme = theme && theme.isDark ? "dark" : "light";
  },
  setEditable(isEditable) {
    editor.setEditable(!!isEditable);
  },
  focusEditor() {
    editor.commands.focus();
  },
};
