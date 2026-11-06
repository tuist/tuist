// @vitest-environment happy-dom
import {afterEach, beforeEach, describe, expect, it, vi} from "vitest"
import CodeEditor, {highlightSource} from "./code_editor"

let observer
beforeEach(() => {
  vi.useFakeTimers()
  vi.stubGlobal("requestAnimationFrame", callback => setTimeout(callback, 0))
  vi.stubGlobal("cancelAnimationFrame", clearTimeout)
  vi.stubGlobal("ResizeObserver", class {
    constructor(callback) { this.callback = callback; this.disconnect = vi.fn(); observer = this }
    observe() {}
  })
})
afterEach(() => {
  document.body.innerHTML = ""
  vi.restoreAllMocks()
  vi.unstubAllGlobals()
  vi.useRealTimers()
})

function editor(source = '{"message":"Hello"}') {
  document.body.innerHTML = '<form><div data-part="code-editor" data-language="json"><textarea></textarea><pre data-part="code-editor-highlight"><code></code></pre></div></form>'
  const el = document.querySelector("[data-part=code-editor]")
  const textarea = el.querySelector("textarea")
  textarea.value = source
  Object.defineProperties(el, {offsetWidth: {value: 400}, offsetHeight: {value: 240}})
  Object.defineProperties(textarea, {clientWidth: {value: 376, configurable: true}, clientHeight: {value: 200}})
  el.getBoundingClientRect = () => ({left: 0, top: 0, width: 400, height: 240})
  textarea.getBoundingClientRect = () => ({left: 12, top: 24, width: 376, height: 200})
  const hook = {...CodeEditor, el}
  hook.mounted()
  return hook
}

function input(hook, value) {
  hook.textarea.value = value
  hook.textarea.dispatchEvent(new Event("input", {bubbles: true}))
  vi.runAllTimers()
}

describe("code editor", () => {
  it("highlights JSON without replacing the real form input", () => {
    const hook = editor()
    expect(hook.el.dataset.enhanced).toBe("true")
    expect(hook.code.querySelector('[data-token~="hljs-string"]')).not.toBeNull()
    expect(hook.code.textContent).toBe(hook.textarea.value)
    expect(hook.textarea.value).toBe('{"message":"Hello"}')
    expect(hook.mirror.style.left).toBe("12px")
    expect(hook.mirror.style.top).toBe("24px")
    expect(hook.mirror.style.width).toBe("376px")
    hook.destroyed()
  })

  it("aligns the mirror in layout coordinates inside scaled modal animations", () => {
    const hook = editor()
    hook.el.getBoundingClientRect = () => ({left: 0, top: 0, width: 360, height: 216})
    hook.textarea.getBoundingClientRect = () => ({left: 10.8, top: 21.6, width: 338.4, height: 180})
    hook.syncViewport()
    expect(hook.mirror.style.left).toBe("12px")
    expect(hook.mirror.style.top).toBe("24px")
    expect(hook.mirror.style.width).toBe("376px")
    hook.destroyed()
  })

  it("updates while typing and preserves the native cursor through server echoes", () => {
    const hook = editor()
    input(hook, '{"draft":')
    hook.textarea.setSelectionRange(5, 5)
    hook.updated()
    expect(hook.textarea.value).toBe('{"draft":')
    expect(hook.textarea.selectionStart).toBe(5)
    expect(hook.code.textContent).toBe('{"draft":')
    hook.destroyed()
  })

  it("switches language without changing the source", () => {
    const hook = editor("return {answer: 42};")
    hook.el.dataset.language = "javascript"
    hook.updated()
    expect(hook.code.querySelector('[data-token~="hljs-keyword"]').textContent).toBe("return")
    expect(hook.textarea.value).toBe("return {answer: 42};")
    hook.destroyed()
  })

  it("escapes HTML-looking source instead of creating elements or executing JavaScript", () => {
    const source = JSON.stringify({message: '<img src=x onerror="alert(1)"><script>alert(1)</script>'})
    const hook = editor(source)
    expect(hook.code.querySelector("script, img")).toBeNull()
    expect(hook.code.textContent).toBe(source)
    expect(hook.code.querySelector("[class]")).toBeNull()
    hook.destroyed()
  })

  it("preserves trailing newlines and synchronizes scrolling", () => {
    const hook = editor('{\n  "message": "Hello"\n}\n')
    expect(hook.code.textContent).toBe(hook.textarea.value + " ")
    hook.textarea.scrollTop = 40
    hook.textarea.scrollLeft = 12
    hook.textarea.dispatchEvent(new Event("scroll"))
    expect(hook.mirror.scrollTop).toBe(40)
    expect(hook.mirror.scrollLeft).toBe(12)
    hook.destroyed()
  })

  it("keeps IME composition in the visible native textarea", () => {
    const hook = editor()
    hook.textarea.dispatchEvent(new Event("compositionstart"))
    expect(hook.el.dataset.enhanced).toBe("false")
    input(hook, '{"name":"日本語"}')
    expect(hook.el.dataset.enhanced).toBe("false")
    hook.textarea.dispatchEvent(new Event("compositionend"))
    vi.runAllTimers()
    expect(hook.el.dataset.enhanced).toBe("true")
    expect(hook.code.textContent).toBe(hook.textarea.value)
    hook.destroyed()
  })

  it("falls back to an untruncated native input for large documents and unsupported languages", () => {
    const hook = editor("x".repeat(65_537))
    expect(hook.el.dataset.enhanced).toBe("false")
    expect(hook.textarea.value.length).toBe(65_537)
    input(hook, "source")
    hook.el.dataset.language = "unknown"
    hook.updated()
    expect(hook.el.dataset.enhanced).toBe("false")
    expect(hook.textarea.value).toBe("source")
    expect(highlightSource("é".repeat(40_000), "json")).toBeNull()
    expect(highlightSource("0,".repeat(32_768), "json")).toBeNull()
    hook.destroyed()
  })

  it("recovers when a hidden modal becomes measurable and cleans up on destruction", () => {
    const hook = editor()
    Object.defineProperty(hook.textarea, "clientWidth", {value: 0, configurable: true})
    observer.callback()
    expect(hook.el.dataset.enhanced).toBe("false")
    Object.defineProperty(hook.textarea, "clientWidth", {value: 376})
    observer.callback()
    expect(hook.el.dataset.enhanced).toBe("true")
    const refresh = vi.spyOn(hook, "refresh")
    hook.onInput()
    hook.destroyed()
    vi.runAllTimers()
    expect(refresh).not.toHaveBeenCalled()
    expect(observer.disconnect).toHaveBeenCalledOnce()
    expect(hook.el.dataset.enhanced).toBeUndefined()
  })
})
