import { Crepe } from '@milkdown/crepe'
import { editorViewCtx } from '@milkdown/kit/core'
import { TextSelection } from '@milkdown/kit/prose/state'
import { replaceAll } from '@milkdown/kit/utils'
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
  const view = crepe.editor.action((ctx) => ctx.get(editorViewCtx))
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

crepe.on((listener) => {
  listener.markdownUpdated((_, markdown, previousMarkdown) => {
    lastMarkdown = markdown
    if (applyingNativeUpdate || markdown === previousMarkdown) return
    post('turbodocMarkdown', { markdown })
  })
})

const setMarkdown = (markdown) => {
  const value = typeof markdown === 'string' ? markdown : ''
  if (value === lastMarkdown) return

  applyingNativeUpdate = true
  crepe.editor.action(replaceAll(value))
  lastMarkdown = value
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
    post('turbodocReady')
  })
  .catch((error) => {
    post('turbodocLog', {
      level: 'error',
      message: String(error),
    })
  })
