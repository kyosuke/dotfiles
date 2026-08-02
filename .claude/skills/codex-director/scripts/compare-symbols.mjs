// Extract top-level declarations by name and compare them across a file split.
// Usage: node compare-symbols.mjs <old-file> <new-file...>
import { readFileSync } from "node:fs";

const declaration = /^(?:export\s+)?(?:declare\s+)?(?:async\s+)?(?:const|let|function|class|type|interface)\s+([A-Za-z0-9_$]+)/;

const symbols = (path) => {
  const lines = readFileSync(path, "utf8").split("\n");
  const found = new Map();
  for (let index = 0; index < lines.length; index += 1) {
    const match = declaration.exec(lines[index]);
    if (match === null) continue;
    // Consume until the declaration's brackets balance and it ends with ; or }
    let depth = 0;
    let text = "";
    let cursor = index;
    for (; cursor < lines.length; cursor += 1) {
      const line = lines[cursor];
      text += line + "\n";
      for (const character of line) {
        if ("{([".includes(character)) depth += 1;
        if ("})]".includes(character)) depth -= 1;
      }
      if (depth <= 0 && cursor > index) break;
      if (depth <= 0 && /[;}]\s*$/.test(line)) break;
    }
    index = cursor;
    found.set(match[1], text.replace(/\s+/g, " ").trim());
  }
  return found;
};

const [oldPath, ...newPaths] = process.argv.slice(2);
const before = symbols(oldPath);
const after = new Map();
for (const path of newPaths) {
  for (const [name, body] of symbols(path)) {
    if (after.has(name)) console.log(`DUPLICATE across new files: ${name}`);
    after.set(name, body);
  }
}

const missing = [];
const changed = [];
const added = [];
for (const [name, body] of before) {
  if (!after.has(name)) missing.push(name);
  else if (after.get(name) !== body) changed.push(name);
}
for (const name of after.keys()) if (!before.has(name)) added.push(name);

console.log(`identical: ${[...before.keys()].filter((n) => after.get(n) === before.get(n)).length}/${before.size}`);
console.log(`MISSING (in old, not in new): ${missing.join(", ") || "none"}`);
console.log(`ADDED (new only): ${added.join(", ") || "none"}`);
console.log(`CHANGED bodies: ${changed.join(", ") || "none"}`);
for (const name of changed) {
  console.log(`\n--- ${name}\nOLD: ${before.get(name)}\nNEW: ${after.get(name)}`);
}
