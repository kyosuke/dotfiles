// Compare the multiset of template literals (SQL + GraphQL) across a file split.
import { readFileSync } from "node:fs";
const literals = (paths) => {
  const all = [];
  for (const path of paths) {
    const source = readFileSync(path, "utf8");
    // crude backtick-string scanner that respects ${...} nesting
    for (let i = 0; i < source.length; i += 1) {
      if (source[i] !== "`") continue;
      let j = i + 1, depth = 0, text = "";
      for (; j < source.length; j += 1) {
        if (source[j] === "\\") { text += source.slice(j, j + 2); j += 1; continue; }
        if (source[j] === "$" && source[j + 1] === "{") depth += 1;
        if (source[j] === "}" && depth > 0) depth -= 1;
        else if (source[j] === "`" && depth === 0) break;
        text += source[j];
      }
      i = j;
      const normalized = text.replace(/\s+/g, " ").trim();
      if (normalized.length > 0) all.push(normalized);
    }
  }
  return all.sort();
};
const split = process.argv.indexOf("--");
const before = literals(process.argv.slice(2, split));
const after = literals(process.argv.slice(split + 1));
const count = (list) => list.reduce((m, v) => m.set(v, (m.get(v) ?? 0) + 1), new Map());
const [b, a] = [count(before), count(after)];
let mismatches = 0;
for (const [text, n] of b) if ((a.get(text) ?? 0) !== n) { mismatches += 1; console.log(`ONLY/COUNT-DIFF in OLD (x${n} vs x${a.get(text) ?? 0}):\n  ${text.slice(0, 300)}\n`); }
for (const [text, n] of a) if (!b.has(text)) { mismatches += 1; console.log(`NEW-ONLY (x${n}):\n  ${text.slice(0, 300)}\n`); }
console.log(`old literals: ${before.length}, new literals: ${after.length}, mismatches: ${mismatches}`);
