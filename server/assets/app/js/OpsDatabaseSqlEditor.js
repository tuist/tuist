/**
 * Client-side bindings for /ops/db's SQL editor.
 *
 * Two responsibilities, both attached via `phx-hook` on the editor
 * <form>:
 *
 *   1. **Cmd/Ctrl + Enter submit.** Listening on the form (capture
 *      phase, keydown) catches the shortcut whether focus is on the
 *      textarea, the Run button, or anywhere else inside the form,
 *      then `requestSubmit()`s so LiveView's `phx-submit="run_query"`
 *      runs the same path the Run button does.
 *
 *   2. **Result export.** The LiveView's `handle_event("export", ...)`
 *      builds the serialized payload (Markdown / JSON / CSV) on the
 *      server and pushes it back via `push_event("ops-db-export",
 *      ...)`. We listen for that event on the hook and either copy
 *      the payload to the clipboard or trigger a CSV download —
 *      depending on the `format` field.
 *
 * Both pieces live in the same hook so a single phx-hook attribute on
 * the editor <form> gives us the whole interaction surface.
 */
export default {
  mounted() {
    this.onKeydown = (event) => {
      if (event.key !== "Enter") return;
      if (!event.metaKey && !event.ctrlKey) return;
      event.preventDefault();
      this.el.requestSubmit();
    };

    this.el.addEventListener("keydown", this.onKeydown);

    this.handleEvent("ops-db-export", ({ format, payload, filename }) => {
      if (format === "download-csv") {
        downloadAs(payload, filename, "text/csv");
      } else {
        copyToClipboard(payload);
      }
    });
  },

  destroyed() {
    if (this.onKeydown) this.el.removeEventListener("keydown", this.onKeydown);
  },
};

function copyToClipboard(text) {
  // navigator.clipboard.writeText is the canonical path; document.execCommand
  // is a fallback for older browsers + non-secure contexts where the modern
  // API rejects. Both are best-effort — if the user denies clipboard
  // permission we silently swallow rather than throwing on the hook side.
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text).catch(() => fallbackCopy(text));
  } else {
    fallbackCopy(text);
  }
}

function fallbackCopy(text) {
  const ta = document.createElement("textarea");
  ta.value = text;
  ta.style.position = "fixed";
  ta.style.opacity = "0";
  document.body.appendChild(ta);
  ta.select();
  try {
    document.execCommand("copy");
  } finally {
    document.body.removeChild(ta);
  }
}

function downloadAs(payload, filename, mime) {
  const blob = new Blob([payload], { type: mime });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  URL.revokeObjectURL(url);
}
