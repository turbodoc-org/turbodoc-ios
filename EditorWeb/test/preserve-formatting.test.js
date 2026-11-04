// Port of turbodoc-web-v2 preserve-formatting.test.ts. Run: pnpm test
import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { preserveSourceFormatting } from '../src/preserve-formatting.js'

// Markdown as written on the web or by an agent, and how the editor
// re-serialises it.
const source = '# Groceries\n\n* milk\n* eggs\n\nSome *emphasis* here.\n'
const loadedAsEdited = '# Groceries\n\n- milk\n- eggs\n\nSome _emphasis_ here.'

describe('preserveSourceFormatting', () => {
  it('returns the source unchanged when the user has not edited anything', () => {
    assert.equal(preserveSourceFormatting(source, loadedAsEdited, loadedAsEdited), source)
  })

  it('applies an edit without reformatting untouched lines', () => {
    const edited = '# Groceries for Sunday\n\n- milk\n- eggs\n\nSome _emphasis_ here.'
    assert.equal(
      preserveSourceFormatting(source, loadedAsEdited, edited),
      '# Groceries for Sunday\n\n* milk\n* eggs\n\nSome *emphasis* here.\n'
    )
  })

  it("keeps an added line in the editor's form and the rest as written", () => {
    const edited = '# Groceries\n\n- milk\n- eggs\n- bread\n\nSome _emphasis_ here.'
    assert.equal(
      preserveSourceFormatting(source, loadedAsEdited, edited),
      '# Groceries\n\n* milk\n* eggs\n- bread\n\nSome *emphasis* here.\n'
    )
  })

  it('uses the edited version of a line the editor also reformatted', () => {
    const edited = '# Groceries\n\n- oat milk\n- eggs\n\nSome _emphasis_ here.'
    assert.equal(
      preserveSourceFormatting(source, loadedAsEdited, edited),
      '# Groceries\n\n- oat milk\n* eggs\n\nSome *emphasis* here.\n'
    )
  })

  it('passes edits through when the editor did not reformat anything', () => {
    assert.equal(preserveSourceFormatting('a\nb', 'a\nb', 'a\nB'), 'a\nB')
  })
})
