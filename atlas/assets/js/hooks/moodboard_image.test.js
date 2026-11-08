// @vitest-environment happy-dom
import {describe, expect, it} from "vitest"
import MoodboardImage from "./moodboard_image"

function image(complete, naturalWidth) {
  const el = document.createElement("img")
  Object.defineProperty(el, "complete", {value: complete, configurable: true})
  Object.defineProperty(el, "naturalWidth", {value: naturalWidth, configurable: true})
  return el
}

function mount(el) {
  const hook = {...MoodboardImage, el}
  hook.mounted()
  return hook
}

describe("MoodboardImage", () => {
  it("hides an already broken image so the hostname fallback remains visible", () => {
    const el = image(true, 0)
    const hook = mount(el)
    expect(el.hidden).toBe(true)
    hook.destroyed()
  })

  it("handles errors and restores a successfully loaded replacement", () => {
    const el = image(false, 0)
    const hook = mount(el)
    expect(el.hidden).toBe(false)
    el.dispatchEvent(new Event("error"))
    expect(el.hidden).toBe(true)
    el.dispatchEvent(new Event("load"))
    expect(el.hidden).toBe(false)
    hook.destroyed()
    el.dispatchEvent(new Event("error"))
    expect(el.hidden).toBe(false)
  })

  it("preserves cached images and resets hidden state after a patch", () => {
    const el = image(true, 400)
    const hook = mount(el)
    expect(el.hidden).toBe(false)
    el.hidden = true
    hook.updated()
    expect(el.hidden).toBe(false)
    hook.destroyed()
  })
})
