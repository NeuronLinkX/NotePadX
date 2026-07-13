import { common, createLowlight } from "lowlight";
import cmake from "highlight.js/lib/languages/cmake";

// 스펙 7절 최소 지원 언어. `common` 번들에 대부분 포함되어 있고 cmake만 별도 등록한다.
// html은 highlight.js에서 xml 문법(alias: html)을 사용한다.
export const lowlight = createLowlight(common);
lowlight.register({ cmake });

export const SUPPORTED_LANGUAGES = [
  { value: "c", label: "C" },
  { value: "cpp", label: "C++" },
  { value: "rust", label: "Rust" },
  { value: "swift", label: "Swift" },
  { value: "python", label: "Python" },
  { value: "java", label: "Java" },
  { value: "javascript", label: "JavaScript" },
  { value: "typescript", label: "TypeScript" },
  { value: "json", label: "JSON" },
  { value: "yaml", label: "YAML" },
  { value: "xml", label: "XML" },
  { value: "html", label: "HTML" },
  { value: "css", label: "CSS" },
  { value: "bash", label: "Bash" },
  { value: "sql", label: "SQL" },
  { value: "cmake", label: "CMake" },
  { value: "markdown", label: "Markdown" },
  { value: "plaintext", label: "Plain Text" },
];
