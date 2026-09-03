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

// 확장자별로 실제 앱 아이콘과 비슷한 색·라벨을 붙인 "문서 + 접힌 모서리" 모양 SVG를 만든다.
// 실제 macOS 파일 아이콘을 가져올 방법이 WKWebView 안에는 없으므로, 한글(HWP)·PDF·Word처럼
// 파일 종류를 한눈에 구분할 수 있는 색상 코드를 대신 쓴다.
const FILE_KIND_BY_EXTENSION = {
  pdf: { label: "PDF", color: "#E5493D" },
  doc: { label: "DOC", color: "#2B579A" },
  docx: { label: "DOC", color: "#2B579A" },
  xls: { label: "XLS", color: "#1D6F42" },
  xlsx: { label: "XLS", color: "#1D6F42" },
  csv: { label: "CSV", color: "#1D6F42" },
  ppt: { label: "PPT", color: "#C43E1C" },
  pptx: { label: "PPT", color: "#C43E1C" },
  hwp: { label: "한글", color: "#1C6DD0" },
  hwpx: { label: "한글", color: "#1C6DD0" },
  zip: { label: "ZIP", color: "#8E8E93" },
  rar: { label: "ZIP", color: "#8E8E93" },
  "7z": { label: "ZIP", color: "#8E8E93" },
  txt: { label: "TXT", color: "#8E8E93" },
};

function fileKind(mimeType, fileName) {
  const ext = String(fileName || "").split(".").pop().toLowerCase();
  if (FILE_KIND_BY_EXTENSION[ext]) return FILE_KIND_BY_EXTENSION[ext];
  if (mimeType && mimeType.startsWith("text/")) return { label: "TXT", color: "#8E8E93" };
  return { label: "", color: "#8E8E93" };
}

/** 문서 한 장 + 오른쪽 위 접힌 모서리 + 하단 색 라벨 모양의 파일 아이콘 SVG. */
function fileIconSVG(mimeType, fileName) {
  const { label, color } = fileKind(mimeType, fileName);
  const labelSVG = label
    ? `<rect x="4" y="46" width="40" height="16" rx="3" fill="${color}"/>
       <text x="24" y="58" text-anchor="middle" font-size="10" font-weight="700" fill="#ffffff"
             font-family="-apple-system, BlinkMacSystemFont, sans-serif">${label}</text>`
    : "";
  return `
    <svg viewBox="0 0 48 60" width="40" height="50" xmlns="http://www.w3.org/2000/svg">
      <path d="M6 2 H30 L42 14 V58 H6 Z" style="fill:var(--nx-bg); stroke:var(--nx-border); stroke-width:1.5"/>
      <path d="M30 2 L42 14 H30 Z" style="fill:var(--nx-border)"/>
      ${labelSVG}
    </svg>
  `;
}

function formatByteSize(bytes) {
  if (!bytes || bytes <= 0) return "";
  const units = ["B", "KB", "MB", "GB"];
  let value = bytes;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  const precision = unitIndex === 0 || value >= 10 ? 0 : 1;
  return `${value.toFixed(precision)} ${units[unitIndex]}`;
}

// 첨부파일 카드. 실제 바이트는 문서(JSON)가 아니라 앱 전용 Attachments 폴더에 저장되고
// (AttachmentStorage.swift), 여기 노드에는 attachmentId·파일명·크기·MIME 타입만 참조로
// 남는다 — 큰 파일을 노트마다 base64로 통째로 들고 있지 않기 위해서다. 클릭하면
// onOpenAttachment(configure로 주입, editor.js가 Swift로 openAttachment 브리지 메시지를
// 보내도록 연결한다)를 호출해 기본 앱으로 연다.
export const FileAttachment = Node.create({
  name: "fileAttachment",
  group: "block",
  atom: true,
  addOptions() {
    return { onOpenAttachment: () => {} };
  },
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
  addNodeView() {
    const openAttachment = this.options.onOpenAttachment;
    return ({ node }) => {
      // 아이콘이 위, 파일명(+크기)이 그 아래 — Finder 아이콘 보기/macOS Notes 첨부파일과
      // 같은 배치. 파일 종류(PDF·한글·Word 등)는 아이콘 색·라벨로 구분하고, 실제 이름은
      // 항상 아이콘 밑에 그대로 보여준다.
      const wrapper = document.createElement("div");
      wrapper.className = "nx-file-attachment";
      wrapper.contentEditable = "false";
      wrapper.dataset.fileAttachment = "";
      wrapper.title = "클릭하면 기본 앱으로 엽니다";

      const icon = document.createElement("div");
      icon.className = "nx-file-attachment-icon";
      icon.innerHTML = fileIconSVG(node.attrs.mimeType, node.attrs.fileName);

      const name = document.createElement("span");
      name.className = "nx-file-attachment-name";
      name.textContent = node.attrs.fileName || "첨부파일";

      const size = document.createElement("span");
      size.className = "nx-file-attachment-size";
      size.textContent = formatByteSize(node.attrs.byteSize);

      wrapper.appendChild(icon);
      wrapper.appendChild(name);
      wrapper.appendChild(size);

      wrapper.addEventListener("click", () => {
        openAttachment(node.attrs.attachmentId, node.attrs.fileName);
      });

      return {
        dom: wrapper,
        update: updatedNode => {
          if (updatedNode.type.name !== "fileAttachment") return false;
          name.textContent = updatedNode.attrs.fileName || "첨부파일";
          size.textContent = formatByteSize(updatedNode.attrs.byteSize);
          icon.innerHTML = fileIconSVG(updatedNode.attrs.mimeType, updatedNode.attrs.fileName);
          node = updatedNode;
          return true;
        },
      };
    };
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

      // wrapper의 CSS width: fit-content가 실측 기준으로 실제로는 작동하지 않아서(이 WKWebView
      // 환경에서 block 요소가 그냥 auto width로 컨테이너 전체 폭을 채워버림), 손잡이(절대
      // 위치, wrapper 기준 right/bottom)가 이미지의 실제 오른쪽 아래 모서리가 아니라 훨씬
      // 넓은 wrapper의 모서리에 붙어서 이미지와 수십 px씩 떨어져 보이는 원인이었다. img가
      // (max-width/max-height로 제한된) 자기 실제 크기로 다 그려진 뒤, 그 실측 폭을 wrapper에
      // 그대로 못박아서 wrapper가 이미지 크기에 정확히 맞춰지게 한다. 사용자가 손잡이로 이미
      // 직접 크기를 지정한 경우(node.attrs.width)는 그 값이 우선이므로 여기서 건드리지 않는다.
      function syncWrapperWidthToRenderedImage() {
        if (node.attrs.width) return;
        if (!img.naturalWidth) return;
        wrapper.style.width = `${img.getBoundingClientRect().width}px`;
      }
      if (img.complete) {
        syncWrapperWidthToRenderedImage();
      } else {
        img.addEventListener("load", syncWrapperWidthToRenderedImage, { once: true });
      }

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
          node = updatedNode;
          if (updatedNode.attrs.width) {
            wrapper.style.width = `${updatedNode.attrs.width}px`;
            wrapper.classList.add("nx-image-resized");
          } else {
            // 그냥 width를 지워버리면(예전 코드) wrapper가 다시 fit-content(실제로는 안 먹는)에
            // 기대게 되어 손잡이가 또 어긋난다 — 대신 실제 렌더된 이미지 크기로 다시 맞춘다.
            wrapper.classList.remove("nx-image-resized");
            syncWrapperWidthToRenderedImage();
          }
          return true;
        },
      };
    };
  },
});
