import "../css/docs.css"
import Noora from "noora"
import {setupCodeCopy} from "./docs/code-copy"
import {copyTextToClipboard} from "./docs/clipboard"

const sidebar = document.getElementById("docs-sidebar")
const menu = document.getElementById("docs-mobile-menu-trigger")
const toc = document.getElementById("docs-mobile-toc")
const tocTrigger = document.getElementById("docs-mobile-toc-trigger")
function closeMenu() {
  document.body.removeAttribute("data-sidebar-open")
  sidebar.removeAttribute("data-mobile-open")
  menu.setAttribute("aria-expanded", "false")
}
menu.addEventListener("click", () => {
  const open = menu.getAttribute("aria-expanded") !== "true"
  document.body.toggleAttribute("data-sidebar-open", open)
  sidebar.toggleAttribute("data-mobile-open", open)
  menu.setAttribute("aria-expanded", String(open))
  if (open) sidebar.querySelector("a").focus()
})
document.getElementById("docs-mobile-sidebar-overlay").addEventListener("click", closeMenu)
tocTrigger?.addEventListener("click", () => {
  const open = toc.dataset.state !== "open"
  toc.dataset.state = open ? "open" : "closed"
  tocTrigger?.setAttribute("aria-expanded", String(open))
})
toc.addEventListener("click", () => {
  toc.dataset.state = "closed"
  tocTrigger?.setAttribute("aria-expanded", "false")
})
document.addEventListener("keydown", event => {
  if (event.key === "Escape" && !document.querySelector('[data-part="copy-dropdown"] [data-part="trigger"][data-state="open"]')) {
    closeMenu()
    toc.dataset.state = "closed"
    tocTrigger?.setAttribute("aria-expanded", "false")
    menu.focus()
  }
})
try {
  document.documentElement.dataset.theme = localStorage.getItem("atlas-docs-theme") || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light")
} catch (_) {}
for (const theme of document.querySelectorAll('[data-part="theme-toggle"]')) theme.addEventListener("click", () => {
  const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark"
  document.documentElement.dataset.theme = next
  try { localStorage.setItem("atlas-docs-theme", next) } catch (_) {}
})


setupCodeCopy(document)

// Noora's portal and menu runtime also serve these static public pages.
for (const portal of document.querySelectorAll("template[data-phx-portal]")) {
  document.querySelector(portal.dataset.phxPortal)?.append(portal.content)
}
for (const el of document.querySelectorAll('[data-part="copy-dropdown"] > [phx-hook="NooraDropdown"]')) {
  const button = el.querySelector('[data-part="main-button"]')
  const label = button.querySelector('[data-part="label"]')
  let resetTimer
  const copyPage = () => {
    const source = document.getElementById("docs-page-markdown").value
    copyTextToClipboard(source).then(() => {
      clearTimeout(resetTimer)
      label.textContent = "Copied"
      resetTimer = setTimeout(() => { label.textContent = "Copy page" }, 3000)
    }).catch(error => console.error("Failed to copy page:", error))
  }
  button.addEventListener("click", copyPage)
  const hook = {...Noora.Hooks.NooraDropdown, el, pushEvent(_event, details) {
    if (details.value === "copy-markdown") copyPage()
  }}
  hook.mounted()
}

for (const el of document.querySelectorAll('[data-part="docs-table"]')) {
  const hook = {...Noora.Hooks.NooraTable, el}
  hook.mounted()
}
