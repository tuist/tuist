// @vitest-environment happy-dom
import {describe, expect, it} from "vitest"
import MoodboardVideo from "./moodboard_video"

describe("MoodboardVideo", () => {
  it("reveals the fallback on error and preserves it across patches", () => {
    const el = document.createElement("video")
    const hook = {...MoodboardVideo, el}
    hook.mounted()
    expect(el.hidden).toBe(false)
    Object.defineProperty(el, "error", {value: {code: 4}, configurable: true})
    el.dispatchEvent(new Event("error"))
    expect(el.hidden).toBe(true)
    hook.updated()
    expect(el.hidden).toBe(true)
    hook.destroyed()
  })

  it("restores a working replacement and removes event listeners when destroyed", () => {
    const el = document.createElement("video")
    const hook = {...MoodboardVideo, el}
    hook.mounted()
    el.dispatchEvent(new Event("error"))
    el.dispatchEvent(new Event("loadedmetadata"))
    expect(el.hidden).toBe(false)
    hook.destroyed()
    el.dispatchEvent(new Event("error"))
    expect(el.hidden).toBe(false)
  })
})
