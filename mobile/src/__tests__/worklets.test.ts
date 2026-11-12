// Animated styles run on the UI thread, where calling a plain JS function
// throws, and in a Release build that kills the app. Jest mocks Reanimated,
// so render tests can't catch it; this checks the source instead.
import { readFileSync, readdirSync, statSync } from 'fs';
import { join, relative } from 'path';

const root = join(__dirname, '..');

function sources(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return name === '__tests__' ? [] : sources(path);
    return /\.tsx?$/.test(name) ? [path] : [];
  });
}

/** The callback passed to each useAnimatedStyle, useAnimatedProps, useAnimatedReaction or useAnimatedScrollHandler. */
function worklets(source: string) {
  const found: { line: number; body: string }[] = [];
  for (const m of source.matchAll(/useAnimated(Style|Props|Reaction|ScrollHandler)\(/g)) {
    let depth = 1;
    let j = m.index! + m[0].length;
    while (depth > 0 && j < source.length) {
      if (source[j] === '(') depth++;
      else if (source[j] === ')') depth--;
      j++;
    }
    found.push({ line: source.slice(0, m.index).split('\n').length, body: source.slice(m.index! + m[0].length, j) });
  }
  return found;
}

// Plain JS helpers from the app; compute their results outside the worklet.
const jsOnly = /(?<![\w.])(C\.\w+|alpha|washTop|cardStyle|useDark|haptic\.\w+|format\w*|initialsFor|toast|set[A-Z]\w*)\(/g;

test('animated styles call no plain JS helpers', () => {
  const problems = sources(root).flatMap((file) =>
    worklets(readFileSync(file, 'utf8')).flatMap(({ line, body }) =>
      [...body.matchAll(jsOnly)].map((m) => `${relative(root, file)}:${line} calls ${m[1]}()`),
    ),
  );
  expect(problems).toEqual([]);
});
