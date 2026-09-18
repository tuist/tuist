import "../css/fonts.css"
import "noora/noora.css"
import "../css/routes/auth.css"
import "../css/layouts/dashboard.css"
import "../css/components/account_dropdown.css"
import "../css/components/pagination.css"
import "../css/components/widget.css"
import "../css/components/search_palette.css"
import "../css/components/platform_icon.css"
import "../css/routes/overview.css"
import "../css/routes/sales.css"
import "../css/routes/finance.css"
import "../css/routes/accounts.css"
import "../css/routes/licenses.css"
import "../css/routes/gtm.css"
import "../css/routes/email.css"
import "../css/routes/support.css"
import "../css/routes/support_chat.css"
import "../css/routes/sessions.css"
import "../css/routes/mcps.css"
import "../css/routes/admin_audit.css"
import "../css/routes/admin_identities.css"
import "../css/routes/admin_users.css"
import "../css/routes/admin_memory.css"
import "../css/routes/admin_inference.css"
import "../css/components/empty_card_section.css"
import "../css/routes/documents.css"
import "../css/routes/document.css"
import "../css/routes/postal.css"
import "../css/routes/hardware.css"
import "../css/routes/financings.css"
import "../css/routes/data_centers.css"
import "../css/routes/insurance.css"
import "../css/routes/notes.css"
import "../css/routes/projects.css"
import "../css/routes/domains.css"
import "../css/routes/errors.css"

import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/atlas"
import Noora from "noora"
import topbar from "../vendor/topbar"
import IdentityChannelDropdownScroll from "./hooks/identity_channel_dropdown_scroll"
import OriginalEmailPreview from "./hooks/original_email_preview"
import ScreenshotPaste from "./hooks/screenshot_paste"
import SearchPalette from "./hooks/search_palette"
import Clipboard from "./hooks/clipboard"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Noora.Hooks, IdentityChannelDropdownScroll, OriginalEmailPreview, ScreenshotPaste, SearchPalette, Clipboard},
})

// Show progress bar on live navigation and form submits. Skipped when the page
// is embedded in an iframe (the support chat widget), where the parent shows
// its own loading state.
const embedded = window.self !== window.top
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => {
  if (!embedded) topbar.show(300)
})
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

window.addEventListener("phx:set-favicon", event => {
  const link = document.getElementById("favicon")
  if (link && event.detail && event.detail.href) {
    link.setAttribute("href", event.detail.href)
  }
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
