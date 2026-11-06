// Full-day leave uses calendar dates, not Noora's analytics-oriented UTC timestamps.
export default function dateOnlyDatePicker(baseHook) {
  return {
    ...baseHook,
    mounted() {
      baseHook.mounted.call(this)
      if (this.el.dataset.dateOnly !== "true") return

      this.datePicker.pushEvent = (event, payload) => {
        const [start, end] = this.datePicker.api.value || []
        if (event === this.el.dataset.onPeriodChange && start && end) {
          const value = {start: start.toString(), end: end.toString()}
          // A fast submit must not wait for the LiveView round trip to update the dates.
          const form = this.el.closest("form")
          for (const [part, date] of [["range-start-input", value.start], ["range-end-input", value.end]]) {
            const input = form?.querySelector(`[data-part="${part}"]`)
            if (input) input.value = date
          }
          payload = {...payload, value}
        }
        this.pushEvent(event, payload)
      }
    },
  }
}
