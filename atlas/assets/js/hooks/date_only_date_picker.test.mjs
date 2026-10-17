import assert from "node:assert/strict"
import test from "node:test"
import dateOnlyDatePicker from "./date_only_date_picker.js"

function mount(dateOnly = "true", dates = ["2026-07-02", "2026-07-04"]) {
  const events = []
  const inputs = {'[data-part="range-start-input"]': {value: ""}, '[data-part="range-end-input"]': {value: ""}}
  const baseHook = {
    mounted() {
      this.datePicker = {
        api: {value: dates.map(date => ({toString: () => date}))},
        pushEvent: (event, payload) => this.pushEvent(event, payload),
      }
    },
    updated() {},
    destroyed() {},
  }
  const hook = dateOnlyDatePicker(baseHook)
  const context = {
    el: {dataset: {dateOnly, onPeriodChange: "holiday_dates_changed"}, closest: () => ({querySelector: selector => inputs[selector]})},
    pushEvent: (event, payload) => events.push({event, payload}),
  }
  hook.mounted.call(context)
  return {context, events, hook, baseHook, inputs}
}

test("uses the selected calendar days rather than UTC timestamps in positive-offset timezones", () => {
  const {context, events, inputs} = mount()
  context.datePicker.pushEvent("holiday_dates_changed", {
    value: {start: "2026-07-01T22:00:00.000Z", end: "2026-07-04T21:59:59.999Z"},
    preset: "custom",
  })
  assert.deepEqual(events[0].payload, {value: {start: "2026-07-02", end: "2026-07-04"}, preset: "custom"})
  assert.equal(inputs['[data-part="range-start-input"]'].value, "2026-07-02")
  assert.equal(inputs['[data-part="range-end-input"]'].value, "2026-07-04")
})

test("preserves inclusive end dates in negative-offset timezones", () => {
  const {context, events} = mount()
  context.datePicker.pushEvent("holiday_dates_changed", {
    value: {start: "2026-07-02T07:00:00.000Z", end: "2026-07-05T06:59:59.999Z"},
  })
  assert.deepEqual(events[0].payload.value, {start: "2026-07-02", end: "2026-07-04"})
})

test("supports single-day ranges and dates spanning daylight-saving changes", () => {
  for (const dates of [["2026-03-29", "2026-03-29"], ["2026-03-28", "2026-03-30"]]) {
    const {context, events} = mount("true", dates)
    context.datePicker.pushEvent("holiday_dates_changed", {value: {}})
    assert.deepEqual(events[0].payload.value, {start: dates[0], end: dates[1]})
  }
})

test("does not change analytics date pickers or the base hook lifecycle", () => {
  const {context, events, hook, baseHook} = mount("false")
  const payload = {value: {start: "2026-07-01T22:00:00Z", end: "2026-07-04T21:59:59Z"}, preset: "custom"}
  context.datePicker.pushEvent("analytics_period_changed", payload)
  assert.equal(events[0].payload, payload)
  assert.equal(hook.updated, baseHook.updated)
  assert.equal(hook.destroyed, baseHook.destroyed)
})

test("passes cancel and unrelated events through without date conversion", () => {
  const {context, events} = mount("true", [])
  context.datePicker.pushEvent("cancel_selection", {})
  assert.deepEqual(events, [{event: "cancel_selection", payload: {}}])
})
