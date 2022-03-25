export const copyToClipboard = (text: string) => {
  navigator.clipboard.writeText(text);
};
