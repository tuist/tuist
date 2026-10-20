const lineHeight = 16
const dropdownSelector = "[data-part='channel-dropdown']"
const itemsSelector =
  ":scope > [data-part='positioner'] > [data-part='content'] > [data-part='items']"

const normalizedDeltaY = (event, element) => {
  if (event.deltaMode === WheelEvent.DOM_DELTA_LINE) return event.deltaY * lineHeight
  if (event.deltaMode === WheelEvent.DOM_DELTA_PAGE) return event.deltaY * element.clientHeight
  return event.deltaY
}

const channelItems = dropdown => dropdown.querySelector(itemsSelector)
const channelItem = (dropdown, target) => {
  const item = target.closest("[data-part='item']")
  if (!item) return null

  const items = channelItems(dropdown)
  if (!items || !items.contains(item)) return null

  return item
}

export default {
  mounted() {
    this.channelDropdownScrollTops = new Map()
    this.pendingScrollRestores = new Set()

    this.storeChannelScrollTop = (dropdown, pendingRestore = false) => {
      const items = channelItems(dropdown)
      if (!items) return

      this.channelDropdownScrollTops.set(dropdown.id, items.scrollTop)
      if (pendingRestore) this.pendingScrollRestores.add(dropdown.id)
    }

    this.restoreChannelScrollTop = dropdown => {
      const storedScrollTop = this.channelDropdownScrollTops.get(dropdown.id)
      if (typeof storedScrollTop !== "number") return

      const items = channelItems(dropdown)
      if (!items) return

      const maxScrollTop = Math.max(0, items.scrollHeight - items.clientHeight)
      items.scrollTop = Math.max(0, Math.min(maxScrollTop, storedScrollTop))
    }

    this.scheduleChannelScrollRestore = dropdownId => {
      if (!this.pendingScrollRestores.has(dropdownId)) return

      window.requestAnimationFrame(() => {
        window.requestAnimationFrame(() => {
          const dropdown = this.el.querySelector(`#${CSS.escape(dropdownId)}`)
          if (dropdown) this.restoreChannelScrollTop(dropdown)
          this.pendingScrollRestores.delete(dropdownId)
        })
      })
    }

    this.handlePointerDown = event => {
      if (!(event.target instanceof Element)) return

      const dropdown = event.target.closest(dropdownSelector)
      if (!dropdown || !this.el.contains(dropdown)) return

      const item = channelItem(dropdown, event.target)
      if (!item) return

      this.storeChannelScrollTop(dropdown, true)
    }

    this.handleClick = event => {
      if (!(event.target instanceof Element)) return

      const dropdown = event.target.closest(dropdownSelector)
      if (!dropdown || !this.el.contains(dropdown)) return

      const item = channelItem(dropdown, event.target)
      if (!item?.dataset.value) return

      // LiveView patches the portal content while Noora ignores the dropdown root,
      // so route item clicks through this stable parent hook.
      this.storeChannelScrollTop(dropdown, true)
      event.preventDefault()
      event.stopPropagation()
      event.stopImmediatePropagation?.()
      this.pushEvent("toggle_identity_channel", {value: item.dataset.value})
    }

    this.handleOpenDropdown = event => {
      if (!event.detail?.id) return
      this.scheduleChannelScrollRestore(event.detail.id)
    }

    this.handleWheel = event => {
      if (!(event.target instanceof Element)) return

      const dropdown = event.target.closest(dropdownSelector)
      if (!dropdown || !this.el.contains(dropdown)) return

      const items = channelItems(dropdown)
      if (!items || !items.contains(event.target)) return

      const maxScrollTop = items.scrollHeight - items.clientHeight
      const scrollTop = items.scrollTop
      const nextScrollTop = Math.max(
        0,
        Math.min(maxScrollTop, scrollTop + normalizedDeltaY(event, items)),
      )

      if (maxScrollTop > 0) items.scrollTop = nextScrollTop
      this.storeChannelScrollTop(dropdown)

      event.preventDefault()
      event.stopPropagation()
    }

    this.el.addEventListener("pointerdown", this.handlePointerDown, {capture: true})
    this.el.addEventListener("click", this.handleClick, {capture: true})
    this.el.addEventListener("wheel", this.handleWheel, {capture: true, passive: false})
    window.addEventListener("phx:open-dropdown", this.handleOpenDropdown)
  },

  updated() {
    for (const dropdownId of this.pendingScrollRestores) {
      this.scheduleChannelScrollRestore(dropdownId)
    }
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this.handlePointerDown, true)
    this.el.removeEventListener("click", this.handleClick, true)
    this.el.removeEventListener("wheel", this.handleWheel, true)
    window.removeEventListener("phx:open-dropdown", this.handleOpenDropdown)
  },
}
