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

// 공식 @tiptap/extension-image를 그대로 쓰지 않고 이름이 같은("image") 커스텀 노드로
// 대체한다 — 이유 두 가지:
//   1) 공식 확장은 allowBase64가 기본 false라서, 이미 삽입된 이미지를 복사해서 다시
//      붙여넣으면(HTML 붙여넣기 경로) data: URI가 거부되어 아예 안 붙는 문제가 있었다.
//   2) 크기 조절 손잡이(모서리 드래그)를 넣으려면 NodeView가 필요한데, 공식 확장은
//      NodeView 없이 <img> 태그만 그린다.
// width 속성은 문서 JSON에 그대로 저장되고(EditorNode.attrs가 임의 값을 보존하므로 Swift
// 쪽 변경 없이 왕복된다), 지정돼 있으면 그 크기로, 없으면 CSS 기본값(최대 480px)으로 보인다.
export const ResizableImage = Node.create({
  name: "image",
  group: "block",
  draggable: true,
  addOptions() {
    return { allowBase64: true, HTMLAttributes: {} };
  },
  addAttributes() {
    return {
      src: { default: null },
      alt: { default: null },
      title: { default: null },
      width: {
        default: null,
        parseHTML: element => {
          const value = element.style.width || element.getAttribute("width");
          return value ? Math.round(parseFloat(value)) : null;
        },
        renderHTML: attrs => (attrs.width ? { style: `width: ${attrs.width}px` } : {}),
      },
    };
  },
  parseHTML() {
    return [{
      tag: this.options.allowBase64 ? "img[src]" : 'img[src]:not([src^="data:"])',
    }];
  },
  renderHTML({ HTMLAttributes }) {
    return ["img", mergeAttributes(this.options.HTMLAttributes, HTMLAttributes)];
  },
  addCommands() {
    return {
      setImage: options => ({ commands }) => commands.insertContent({ type: this.name, attrs: options }),
    };
  },
  addNodeView() {
    return ({ node, editor, getPos }) => {
      const wrapper = document.createElement("div");
      wrapper.className = "nx-image-wrapper";
      if (node.attrs.width) {
        wrapper.style.width = `${node.attrs.width}px`;
        wrapper.classList.add("nx-image-resized");
      }

      const img = document.createElement("img");
      img.src = node.attrs.src || "";
      if (node.attrs.alt) img.alt = node.attrs.alt;
      if (node.attrs.title) img.title = node.attrs.title;
      wrapper.appendChild(img);

      const handle = document.createElement("span");
      handle.className = "nx-image-resize-handle";
      handle.contentEditable = "false";
      wrapper.appendChild(handle);

      let startX = 0;
      let startWidth = 0;

      function commitWidth(width) {
        if (typeof getPos !== "function") return;
        const pos = getPos();
        if (typeof pos !== "number") return;
        const tr = editor.view.state.tr.setNodeMarkup(pos, undefined, { ...node.attrs, width });
        editor.view.dispatch(tr);
      }

      function onPointerMove(event) {
        const delta = event.clientX - startX;
        // 편집기 폭보다 커지면 다시 가로 스크롤 버그가 재발하니, 감싸는 요소 폭으로 상한을 둔다.
        const maxWidth = wrapper.parentElement ? wrapper.parentElement.clientWidth : 4000;
        const newWidth = Math.min(maxWidth, Math.max(60, Math.round(startWidth + delta)));
        wrapper.style.width = `${newWidth}px`;
        wrapper.classList.add("nx-image-resized");
      }

      function onPointerUp() {
        document.removeEventListener("pointermove", onPointerMove);
        document.removeEventListener("pointerup", onPointerUp);
        commitWidth(Math.round(wrapper.getBoundingClientRect().width));
      }

      handle.addEventListener("pointerdown", event => {
        event.preventDefault();
        event.stopPropagation();
        startX = event.clientX;
        startWidth = wrapper.getBoundingClientRect().width;
        document.addEventListener("pointermove", onPointerMove);
        document.addEventListener("pointerup", onPointerUp);
      });

      return {
        dom: wrapper,
        update: updatedNode => {
          if (updatedNode.type.name !== "image") return false;
          if (updatedNode.attrs.src !== node.attrs.src) img.src = updatedNode.attrs.src || "";
          wrapper.style.width = updatedNode.attrs.width ? `${updatedNode.attrs.width}px` : "";
          wrapper.classList.toggle("nx-image-resized", !!updatedNode.attrs.width);
          node = updatedNode;
          return true;
        },
      };
    };
  },
});
