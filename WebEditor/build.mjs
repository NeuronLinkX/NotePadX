import * as esbuild from "esbuild";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const watch = process.argv.includes("--watch");

// 런타임 자산은 npm 빌드 도구(node_modules 포함) 바깥, 앱이 실제로 번들에 담는
// Sources/NotepadX/Resources/WebEditor/dist 로 직접 출력한다.
const outfile = path.join(__dirname, "../Sources/NotepadX/Resources/WebEditor/dist/editor.bundle.js");

/** @type {import('esbuild').BuildOptions} */
const options = {
  entryPoints: [path.join(__dirname, "src/editor.js")],
  outfile,
  bundle: true,
  format: "iife",
  target: ["safari17"],
  platform: "browser",
  minify: true,
  sourcemap: false,
  legalComments: "none",
  logLevel: "info",
};

if (watch) {
  const ctx = await esbuild.context(options);
  await ctx.watch();
  console.log("esbuild watching for changes...");
} else {
  await esbuild.build(options);
}
