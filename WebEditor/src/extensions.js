import { Extension, InputRule, Node, mergeAttributes } from "@tiptap/core";

// 공식 Color/FontFamily 확장과 같은 방식으로 textStyle 마크에 fontSize 속성을 얹는다.
// 별도 마크 타입을 새로 만들지 않아 문서에는 { type: "textStyle", attrs: { fontSize, color, fontFamily } }
// 하나로 합쳐져 저장된다.
export const FontSize = Extension.create({
  name: "fontSize",
  addOptions() {
    return { types: ["textStyle"] };
  },
  addGlobalAttributes() {
    return [
      {
        types: this.options.types,
        attributes: {
          fontSize: {
            default: null,
            parseHTML: element => element.style.fontSize || null,
            renderHTML: attributes => {
              if (!attributes.fontSize) return {};
              return { style: `font-size: ${attributes.fontSize}` };
            },
          },
        },
      },
    ];
  },
  addCommands() {
    return {
      setFontSize: fontSize => ({ chain }) => chain().setMark("textStyle", { fontSize }).run(),
      unsetFontSize: () => ({ chain }) => chain().setMark("textStyle", { fontSize: null }).run(),
    };
  },
});

// 접을 수 있는 세부 블록 (스펙 5절). 네이티브 <details>/<summary>를 그대로 사용해
// WKWebView 안에서 별도 JS 없이도 펼침/접힘이 동작한다.
export const DetailsSummary = Node.create({
  name: "detailsSummary",
  content: "inline*",
  defining: true,
  parseHTML() {
    return [{ tag: "summary" }];
  },
  renderHTML({ HTMLAttributes }) {
    return ["summary", mergeAttributes(HTMLAttributes), 0];
  },
});

export const DetailsContent = Node.create({
  name: "detailsContent",
  content: "block+",
  defining: true,
  parseHTML() {
    return [{ tag: "div[data-details-content]" }];
  },
  renderHTML({ HTMLAttributes }) {
    return ["div", mergeAttributes(HTMLAttributes, { "data-details-content": "" }), 0];
  },
});

export const Details = Node.create({
  name: "details",
  group: "block",
  content: "detailsSummary detailsContent",
  defining: true,
  addAttributes() {
    return {
      open: {
        default: true,
        parseHTML: element => element.hasAttribute("open"),
        renderHTML: attributes => (attributes.open ? { open: "" } : {}),
      },
    };
  },
  parseHTML() {
    return [{ tag: "details" }];
  },
  renderHTML({ HTMLAttributes }) {
    return ["details", mergeAttributes(HTMLAttributes), 0];
  },
  addCommands() {
    return {
      insertDetails: () => ({ chain }) => chain().insertContent({
        type: "details",
        attrs: { open: true },
        content: [
          { type: "detailsSummary", content: [{ type: "text", text: "요약" }] },
          { type: "detailsContent", content: [{ type: "paragraph" }] },
        ],
      }).run(),
    };
  },
});

// 첨부파일 칩. 실제 파일 저장/드래그앤드롭 업로드 파이프라인은 Phase 3(Attachment 서비스)에서
// 연결되며, 여기서는 문서 스키마와 렌더링만 미리 지원한다.
export const FileAttachment = Node.create({
  name: "fileAttachment",
  group: "block",
  atom: true,
  addAttributes() {
    return {
      attachmentId: { default: null },
      fileName: { default: "" },
      byteSize: { default: 0 },
      mimeType: { default: "" },
    };
  },
  parseHTML() {
    return [{ tag: "div[data-file-attachment]" }];
  },
  renderHTML({ node, HTMLAttributes }) {
    return [
      "div",
      mergeAttributes(HTMLAttributes, { "data-file-attachment": "", class: "nx-file-attachment" }),
      `\u{1F4CE} ${node.attrs.fileName || "첨부파일"}`,
    ];
  },
});

// "-->"/"<--"를 입력하면 화살표 문자로 바로 바뀐다. Tiptap 공식 Typography 확장 전체를
// 들여오는 대신, 요청받은 화살표 규칙만 InputRule로 직접 만든다.
function arrowRule(find, replacement) {
  return new InputRule({
    find,
    handler: ({ state, range }) => {
      state.tr.insertText(replacement, range.from, range.to);
    },
  });
}

export const ArrowTypography = Extension.create({
  name: "arrowTypography",
  addInputRules() {
    return [
      arrowRule(/-->$/, "→"),
      arrowRule(/<--$/, "←"),
    ];
  },
});
