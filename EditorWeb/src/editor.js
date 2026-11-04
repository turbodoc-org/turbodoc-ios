import { Crepe } from '@milkdown/crepe'
import {
  editorViewCtx,
  editorViewOptionsCtx,
  remarkStringifyOptionsCtx,
} from '@milkdown/kit/core'
import { redo, redoDepth, undo, undoDepth } from '@milkdown/kit/prose/history'
import { Plugin, TextSelection } from '@milkdown/kit/prose/state'
import { canJoin } from '@milkdown/kit/prose/transform'
import { $prose, replaceAll } from '@milkdown/kit/utils'
import '@milkdown/crepe/theme/common/style.css'
import '@milkdown/crepe/theme/frame.css'
import './editor.css'

const post = (handler, payload = {}) => {
  window.webkit?.messageHandlers?.[handler]?.postMessage(payload)
}

const root = document.querySelector('#editor')
let lastMarkdown = ''
let applyingNativeUpdate = false

const graphemeCount = (text) => {
  if (typeof Intl.Segmenter === 'function') {
    return [...new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(text)]
      .length
  }
  return Array.from(text).length
}

const removeSingleCharacterLine = (event, view) => {
  const { $from, empty } = view.state.selection
  const paragraph = $from.parent
  const isDeletingOnlyCharacter =
    empty &&
    paragraph.type.name === 'paragraph' &&
    $from.parentOffset === paragraph.content.size &&
    graphemeCount(paragraph.textContent) === 1

  if (!isDeletingOnlyCharacter) return false

  let removeFrom
  let removeTo

  if ($from.depth === 1 && $from.index(0) > 0) {
    removeFrom = $from.before()
    removeTo = removeFrom + paragraph.nodeSize
  } else {
    const itemDepth = $from.depth - 1
    const listDepth = itemDepth - 1
    const listItem = $from.node(itemDepth)
    const isSimpleNonFirstListItem =
      listItem?.type.name === 'list_item' &&
      listItem.childCount === 1 &&
      listDepth >= 0 &&
      $from.index(listDepth) > 0

    if (!isSimpleNonFirstListItem) return false

    removeFrom = $from.before(itemDepth)
    removeTo = removeFrom + listItem.nodeSize
  }

  event.preventDefault()
  const transaction = view.state.tr.delete(removeFrom, removeTo)
  const selectionPosition = Math.min(removeFrom, transaction.doc.content.size)
  transaction.setSelection(
    TextSelection.near(transaction.doc.resolve(selectionPosition), -1)
  )
  view.dispatch(transaction)
  view.focus()
  return true
}

const handleBackwardDelete = (event) => {
  const view = getView()
  if (removeSingleCharacterLine(event, view)) return true

  const { $from, empty } = view.state.selection
  const isAtHeadingStart =
    empty &&
    $from.parentOffset === 0 &&
    $from.parent.type.name === 'heading'

  if (!isAtHeadingStart) return false

  event.preventDefault()
  const content = []
  $from.parent.content.forEach((child) => {
    content.push(
      child.mark(child.marks.filter((mark) => mark.type.name !== 'strong'))
    )
  })
  const paragraph = view.state.schema.nodes.paragraph.create(null, content)
  view.dispatch(
    view.state.tr.replaceWith(
      $from.before(),
      $from.before() + $from.parent.nodeSize,
      paragraph
    )
  )
  view.focus()
  return true
}

const getView = () => crepe.editor.action((ctx) => ctx.get(editorViewCtx))

// Milkdown stores list `spread` as the strings 'true' / 'false', which remark
// treats as truthy, so every list was saved loose ("* a\n\n* b").
const joinTightLists = (left, right, parent) => {
  if (parent.type !== 'list' && parent.type !== 'listItem') return undefined
  if (typeof parent.spread !== 'string') return undefined
  // Two paragraphs in one item always need a blank line between them.
  if (left.type === 'paragraph' && right.type === 'paragraph') return undefined
  if (parent.type === 'listItem' && right.type === 'list') return 0
  return parent.spread === 'true' ? 1 : 0
}

// "[ ] ", "[x] " or "- [ ] " typed at the start of a line. Milkdown's own task
// rule only works inside a bullet item and drops the caret back onto the
// previous line, so this one runs first (view props beat plugin props).
const TASK_MARKER = /^\s*(?:[-*+]\s*)?\[([ xX]?)\]$/

const handleTaskMarker = (view, from, to, text) => {
  if (text !== ' ' || from !== to) return false

  const { state } = view
  const $from = state.doc.resolve(from)
  const paragraph = $from.parent
  if (paragraph.type.name !== 'paragraph') return false

  const marker = paragraph.textBetween(0, $from.parentOffset, undefined, '\ufffc')
  const match = TASK_MARKER.exec(marker)
  if (!match) return false

  const checked = match[1].toLowerCase() === 'x'
  const { schema } = state
  const paragraphStart = $from.start()
  const listItem = $from.depth > 1 ? $from.node(-1) : null
  const isFirstChildOfListItem =
    listItem?.type.name === 'list_item' && $from.index(-1) === 0

  let tr = state.tr

  if (isFirstChildOfListItem) {
    if (listItem.attrs.checked != null) return false
    tr = tr
      .delete(paragraphStart, from)
      .setNodeMarkup($from.before(-1), undefined, { ...listItem.attrs, checked })
      .setSelection(TextSelection.create(tr.doc, paragraphStart))
  } else {
    const content = paragraph.content.cut($from.parentOffset)
    const list = schema.nodes.bullet_list.create(
      { spread: 'false' },
      schema.nodes.list_item.create(
        { listType: 'bullet', checked, spread: 'false' },
        schema.nodes.paragraph.create(paragraph.attrs, content)
      )
    )
    const blockStart = $from.before()
    tr = tr.replaceWith(blockStart, $from.after(), list)
    // bullet_list > list_item > paragraph
    tr.setSelection(TextSelection.create(tr.doc, blockStart + 3))

    // Continue a list directly above or below instead of starting a new one.
    const listEnd = blockStart + list.nodeSize
    if (canJoin(tr.doc, listEnd)) tr.join(listEnd)
    if (canJoin(tr.doc, blockStart)) tr.join(blockStart)
  }

  view.dispatch(tr.scrollIntoView())
  return true
}

// Toggle checkboxes on tap without focusing the editor, so the keyboard
// doesn't pop up while ticking items off.
const taskLabelFromEvent = (event) => {
  const wrapper = event.target?.closest?.('.label-wrapper')
  if (!wrapper || !root.contains(wrapper)) return null
  return wrapper.querySelector('.checked, .unchecked') ? wrapper : null
}

const toggleTaskFromLabel = (wrapper) => {
  const view = getView()
  if (!view.editable) return

  const block = wrapper.closest('.milkdown-list-item-block')
  if (!block) return

  const domPos = view.posAtDOM(block, 0)
  const pos = [domPos, domPos - 1].find(
    (candidate) =>
      candidate >= 0 && view.state.doc.nodeAt(candidate)?.type.name === 'list_item'
  )
  if (pos == null) return

  const node = view.state.doc.nodeAt(pos)
  view.dispatch(view.state.tr.setNodeAttribute(pos, 'checked', !node.attrs.checked))
  post('turbodocHaptic', { style: 'selection' })
}

const installTaskToggle = () => {
  const swallow = (event) => {
    if (!taskLabelFromEvent(event)) return
    event.preventDefault()
    event.stopPropagation()
  }

  // Crepe toggles on pointerdown, which fires when a scroll starts on the
  // checkbox. Swallow it and toggle on click (a completed tap) instead.
  root.addEventListener('pointerdown', swallow, true)
  root.addEventListener('mousedown', swallow, true)
  root.addEventListener(
    'click',
    (event) => {
      const wrapper = taskLabelFromEvent(event)
      if (!wrapper) return
      event.preventDefault()
      event.stopPropagation()
      toggleTaskFromLabel(wrapper)
    },
    true
  )
}

let lastHistoryState = ''

const postHistoryState = (state) => {
  const canUndo = undoDepth(state) > 0
  const canRedo = redoDepth(state) > 0
  const key = `${canUndo}:${canRedo}`
  if (key === lastHistoryState) return
  lastHistoryState = key
  post('turbodocHistory', { canUndo, canRedo })
}

const historyStatePlugin = $prose(
  () =>
    new Plugin({
      view: (view) => {
        postHistoryState(view.state)
        return { update: (view) => postHistoryState(view.state) }
      },
    })
)

const crepe = new Crepe({
  root,
  defaultValue: '',
  features: {
    [Crepe.Feature.TopBar]: false,
    [Crepe.Feature.AI]: false,
    [Crepe.Feature.Latex]: false,
    [Crepe.Feature.BlockEdit]: false,
  },
  featureConfigs: {
    [Crepe.Feature.Placeholder]: {
      text: 'Start writing…',
      mode: 'doc',
    },
    [Crepe.Feature.LinkTooltip]: {
      inputPlaceholder: 'Paste or type a link',
    },
  },
})

crepe.editor
  .config((ctx) => {
    ctx.update(remarkStringifyOptionsCtx, (options) => ({
      ...options,
      bullet: '-',
      join: [...(options.join ?? []), joinTightLists],
    }))
    ctx.update(editorViewOptionsCtx, (options) => ({
      ...options,
      handleTextInput: handleTaskMarker,
    }))
  })
  .use(historyStatePlugin)

crepe.on((listener) => {
  listener.markdownUpdated((_, markdown, previousMarkdown) => {
    lastMarkdown = markdown
    if (applyingNativeUpdate || markdown === previousMarkdown) return
    post('turbodocMarkdown', { markdown })
  })
})

const scrollToTop = () => {
  window.scrollTo(0, 0)
  document.scrollingElement?.scrollTo(0, 0)
}

const setMarkdown = (markdown, shouldScrollToTop = false) => {
  const value = typeof markdown === 'string' ? markdown : ''
  if (value === lastMarkdown) return

  applyingNativeUpdate = true
  // Flush so the new document starts a fresh undo history: undoing right
  // after opening a note must not wipe it, and restores can't be undone into
  // a half-merged state.
  crepe.editor.action(replaceAll(value, true))
  lastMarkdown = value

  if (shouldScrollToTop) {
    crepe.editor.action((ctx) => {
      const view = ctx.get(editorViewCtx)
      view.dispatch(
        view.state.tr.setSelection(TextSelection.atStart(view.state.doc))
      )
    })
    scrollToTop()
    requestAnimationFrame(() => {
      scrollToTop()
      requestAnimationFrame(scrollToTop)
    })
  }

  queueMicrotask(() => {
    applyingNativeUpdate = false
  })
}

const setAppearance = (appearance) => {
  document.documentElement.dataset.appearance =
    appearance === 'dark' ? 'dark' : 'light'
}

window.turbodocEditor = {
  setMarkdown,
  setAppearance,
  getMarkdown: () => crepe.getMarkdown(),
  undo: () => {
    const view = getView()
    undo(view.state, view.dispatch)
  },
  redo: () => {
    const view = getView()
    redo(view.state, view.dispatch)
  },
  focusStart: () =>
    crepe.editor.action((ctx) => {
      const view = ctx.get(editorViewCtx)
      view.dispatch(
        view.state.tr.setSelection(TextSelection.create(view.state.doc, 1))
      )
      view.focus()
    }),
  focusBlockEnd: (blockIndex) =>
    crepe.editor.action((ctx) => {
      const view = ctx.get(editorViewCtx)
      let position = null
      view.state.doc.forEach((node, offset, index) => {
        if (index === blockIndex) {
          position = offset + 1 + node.content.size
        }
      })
      if (position === null) return

      view.dispatch(
        view.state.tr.setSelection(TextSelection.create(view.state.doc, position))
      )
      view.focus()
    }),
  focus: () => {
    root.querySelector('[contenteditable="true"]')?.focus()
  },
}

window.addEventListener('error', (event) => {
  post('turbodocLog', {
    level: 'error',
    message: event.message || 'Unknown editor error',
  })
})

window.addEventListener('unhandledrejection', (event) => {
  post('turbodocLog', {
    level: 'error',
    message: String(event.reason || 'Unhandled editor rejection'),
  })
})

crepe
  .create()
  .then(() => {
    document.addEventListener(
      'beforeinput',
      (event) => {
        if (event.inputType !== 'deleteContentBackward') return
        handleBackwardDelete(event)
      },
      true
    )

    document.addEventListener(
      'keydown',
      (event) => {
        if (event.key !== 'Backspace') return
        handleBackwardDelete(event)
      },
      true
    )
    installTaskToggle()
    post('turbodocReady')
  })
  .catch((error) => {
    post('turbodocLog', {
      level: 'error',
      message: String(error),
    })
  })
