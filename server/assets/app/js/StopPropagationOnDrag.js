export default {
  mounted() {
    let dragStartX = 0;
    let dragStartY = 0;
    let hasDragged = false;
    const DRAG_THRESHOLD = 5;

    const handleMouseDown = (event) => {
      dragStartX = event.clientX;
      dragStartY = event.clientY;
      hasDragged = false;
      this.el.addEventListener("mousemove", handleMouseMove);
      this.el.addEventListener("mouseup", handleMouseUp);
    };

    const handleMouseMove = (event) => {
      const deltaX = Math.abs(event.clientX - dragStartX);
      const deltaY = Math.abs(event.clientY - dragStartY);

      if (!hasDragged && (deltaX > DRAG_THRESHOLD || deltaY > DRAG_THRESHOLD)) {
        hasDragged = true;

        document.dispatchEvent(new CustomEvent("handlePropagatedMouseMove", event));
      }
    };

    const handleMouseUp = () => {
      this.el.removeEventListener("mousemove", handleMouseMove);
      this.el.removeEventListener("mouseup", handleMouseUp);
    };

    this.el.addEventListener("click", (event) => {
      if (hasDragged) {
        event.preventDefault();
        event.stopPropagation();
        return false;
      }
    });

    this.el.addEventListener("mousedown", handleMouseDown);
  },
};
