const PlaceCursorAtEnd = {
  mounted() {
    const input = this.el;
    input.focus();

    if (
      input.type === "text" ||
      input.type === "email" ||
      input.type === "password" ||
      input.tagName === "TEXTAREA"
    ) {
      const length = input.value.length;
      input.setSelectionRange(length, length);
    }
  },
};

export { PlaceCursorAtEnd };
