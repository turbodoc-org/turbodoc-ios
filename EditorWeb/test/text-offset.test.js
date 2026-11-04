import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { Schema } from '@milkdown/kit/prose/model'
import { mapTextOffset, positionAtTextOffset, textOffsetAt } from '../src/text-offset.js'

const schema = new Schema({
  nodes: {
    doc: { content: 'block+' },
    paragraph: { group: 'block', content: 'inline*' },
    list: { group: 'block', content: 'item+' },
    item: { content: 'paragraph+' },
    image: { group: 'inline', inline: true },
    text: { group: 'inline' },
  },
})
const p = (...content) =>
  schema.node('paragraph', null, content.map((c) => (typeof c === 'string' ? schema.text(c) : c)))
const list = (...items) => schema.node('list', null, items.map((t) => schema.node('item', null, [p(t)])))

describe('positionAtTextOffset', () => {
  it('inverts textOffsetAt for every caret position', () => {
    const doc = schema.node('doc', null, [
      p(),
      p('ab'),
      list('milk', 'eggs'),
      p(),
      p('c', schema.node('image'), 'd'),
    ])
    for (let pos = 1; pos <= doc.content.size; pos++) {
      if (!doc.resolve(pos).parent.isTextblock) continue
      assert.equal(positionAtTextOffset(doc, textOffsetAt(doc, pos)), pos, `pos ${pos}`)
    }
  })
})

describe('mapTextOffset', () => {
  const before = 'one\ntwo\nthree'

  it('keeps a caret before the change', () => {
    assert.equal(mapTextOffset(2, before, 'one\ntwo!\nthree'), 2)
  })

  it('moves a caret after the change with its text', () => {
    const after = 'zero\none\ntwo\nthree'
    const offset = before.indexOf('three') + 2
    assert.equal(mapTextOffset(offset, before, after), after.indexOf('three') + 2)
  })

  it('clamps a caret inside a removed passage', () => {
    // "tw|o" is removed; the caret lands where it was, before "hree".
    assert.equal(mapTextOffset(6, before, 'one\nthree'), 5)
  })
})
