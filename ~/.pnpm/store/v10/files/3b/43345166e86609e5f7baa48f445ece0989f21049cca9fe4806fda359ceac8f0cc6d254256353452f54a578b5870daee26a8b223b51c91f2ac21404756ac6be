import { useToasts as c } from "@scalar/use-toasts";
function p(t = {}) {
  const { notify: r = (o) => e(o, "info") } = t, { toast: e } = c();
  async function a(o) {
    try {
      await navigator.clipboard.writeText(o), r("Copied to the clipboard");
    } catch (i) {
      console.error(i.message), r("Failed to copy to clipboard");
    }
  }
  return { copyToClipboard: a };
}
export {
  p as useClipboard
};
