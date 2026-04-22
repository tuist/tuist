function legacyCopyTextToClipboard(text) {
  return new Promise((resolve, reject) => {
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.top = "0";
    textarea.style.left = "-9999px";
    textarea.style.opacity = "0";

    document.body.appendChild(textarea);
    textarea.focus({ preventScroll: true });
    textarea.select();
    textarea.setSelectionRange(0, textarea.value.length);

    try {
      if (document.execCommand("copy")) {
        resolve();
      } else {
        reject(new Error("document.execCommand('copy') returned false"));
      }
    } catch (error) {
      reject(error);
    } finally {
      document.body.removeChild(textarea);
    }
  });
}

export function copyTextToClipboard(text) {
  if (navigator.clipboard?.writeText && window.isSecureContext) {
    return navigator.clipboard.writeText(text).catch(() => legacyCopyTextToClipboard(text));
  }

  return legacyCopyTextToClipboard(text);
}
