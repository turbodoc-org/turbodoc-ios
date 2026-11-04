// Port of turbodoc-web-v2 src/components/note/preserve-formatting.ts.
import { diff3Merge } from 'node-diff3'

/** Line alignment is quadratic; larger hunks fall back to the edited lines. */
const MAX_ALIGN_CELLS = 250_000

/**
 * Within one hunk where the editor reformatted each source line into one
 * loaded line, put back the source form of every line the user left as is.
 */
function restoreUntouchedLines(edited, loaded, source) {
  if (loaded.length !== source.length || edited.length * loaded.length > MAX_ALIGN_CELLS) {
    return edited
  }
  // Longest common subsequence of edited and loaded lines.
  const lcs = Array.from({ length: edited.length + 1 }, () =>
    Array.from({ length: loaded.length + 1 }, () => 0)
  )
  for (let i = edited.length - 1; i >= 0; i--) {
    for (let j = loaded.length - 1; j >= 0; j--) {
      lcs[i][j] =
        edited[i] === loaded[j]
          ? lcs[i + 1][j + 1] + 1
          : Math.max(lcs[i + 1][j], lcs[i][j + 1])
    }
  }
  const result = []
  let i = 0
  let j = 0
  while (i < edited.length) {
    if (j < loaded.length && edited[i] === loaded[j]) {
      result.push(source[j])
      i++
      j++
    } else if (j < loaded.length && lcs[i][j + 1] >= lcs[i + 1][j]) {
      j++
    } else {
      result.push(edited[i])
      i++
    }
  }
  return result
}

/**
 * Milkdown re-serialises the whole document on every change (list markers,
 * escaping, emphasis style, trailing newline). Saving that as is would
 * rewrite lines nobody touched: noisy history, and edits from other devices
 * on those lines would conflict with a pure reformat.
 *
 * Given the stored Markdown that was loaded (`source`), the editor's
 * serialisation of it before any edits (`loadedAsEdited`) and its current
 * serialisation (`edited`), this returns `source` with only the user's
 * changes applied. Lines the user did not change keep their original form.
 */
export function preserveSourceFormatting(source, loadedAsEdited, edited) {
  if (edited === loadedAsEdited) return source
  if (source === loadedAsEdited) return edited

  const lines = []
  for (const region of diff3Merge(
    edited.split('\n'),
    loadedAsEdited.split('\n'),
    source.split('\n'),
    { excludeFalseConflicts: true }
  )) {
    if (region.ok) lines.push(...region.ok)
    // The user edited near lines the editor reformatted: keep their edits and
    // restore the lines they did not touch.
    else if (region.conflict) {
      const { a: editedLines, o: loadedLines, b: sourceLines } = region.conflict
      lines.push(...restoreUntouchedLines(editedLines, loadedLines, sourceLines))
    }
  }
  return lines.join('\n')
}
