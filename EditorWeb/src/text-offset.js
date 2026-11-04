// Text offsets let the caret survive a document replacement: positions
// shift with node structure, the text before the caret mostly does not.
const LEAF_TEXT = '\ufffc'

export const textOffsetAt = (doc, pos) => doc.textBetween(0, pos, '\n', LEAF_TEXT).length

// Inverse of `textOffsetAt`, mirroring how ProseMirror's textBetween counts
// block separators and leaf nodes.
export const positionAtTextOffset = (doc, offset) => {
  let count = 0
  let first = true
  let result = null
  doc.descendants((node, pos) => {
    if (result !== null) return false
    const nodeText = node.isText ? node.text : node.isLeaf ? LEAF_TEXT : ''
    if (node.isBlock && ((node.isLeaf && nodeText) || node.isTextblock)) {
      if (first) {
        first = false
        if (offset <= 0) {
          result = node.isTextblock ? pos + 1 : pos
          return false
        }
      } else {
        count += 1
        if (count >= offset) {
          result = node.isTextblock ? pos + 1 : pos
          return false
        }
      }
    }
    if (nodeText) {
      if (count + nodeText.length >= offset) {
        result = pos + (offset - count)
        return false
      }
      count += nodeText.length
    }
    return true
  })
  return result ?? doc.content.size
}

export const fullText = (doc) => doc.textBetween(0, doc.content.size, '\n', LEAF_TEXT)

// Where a text offset in `before` ends up in `after`. Text the caret follows
// that did not change keeps it in place, even when text above it changed.
export const mapTextOffset = (offset, before, after) => {
  let prefix = 0
  const maxPrefix = Math.min(before.length, after.length)
  while (prefix < maxPrefix && before[prefix] === after[prefix]) prefix++
  if (offset <= prefix) return offset

  let suffix = 0
  const maxSuffix = maxPrefix - prefix
  while (
    suffix < maxSuffix &&
    before[before.length - 1 - suffix] === after[after.length - 1 - suffix]
  ) {
    suffix++
  }
  if (offset >= before.length - suffix) return offset + (after.length - before.length)
  // Inside the changed part: stay put, clamped to it.
  return Math.min(offset, after.length - suffix)
}
