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
import ImageExtension from "@tiptap/extension-image";

import { lowlight } from "./languages.js";
import { sanitizePastedHTML } from "./sanitize.js";
import { FontSize, Details, DetailsSummary, DetailsContent, FileAttachment } from "./extensions.js";

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
  }, 150);
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
  ImageExtension,
  Details,
  DetailsSummary,
  DetailsContent,
  FileAttachment,
];

const editor = new Editor({
  element: document.querySelector("#editor-root"),
  extensions,
  content: { type: "doc", content: [{ type: "paragraph" }] },
  autofocus: false,
  editorProps: {
    transformPastedHTML: sanitizePastedHTML,
    handleClickOn(_view, _pos, _node, _nodePos, event) {
      const target = event.target && event.target.closest ? event.target.closest("a[href]") : null;
      if (target) {
        event.preventDefault();
        postToNative("openExternalLink", { url: target.getAttribute("href") });
        return true;
      }
      return false;
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
  setFontSize: args => editor.chain().focus().setFontSize((args && args.px) || "16px").run(),
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
    // 방금 불러온 문서를 즉시 "변경됨"으로 재저장하는 루프를 막는다.
    editor.commands.setContent({ type: "doc", content }, false);
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
