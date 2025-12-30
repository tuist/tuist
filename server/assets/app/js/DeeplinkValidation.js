export default {
  mounted() {
    let blurred = false;
    this.handleBlur = () => {
      blurred = true;
    };

    this.handleOnClick = () => {
      blurred = false;
      setTimeout(() => {
        if (!blurred) {
          this.el.style.display = "flex";
        }
      }, 100);
    };
    const deeplinkElement = document.querySelector(`#${this.el.dataset.deeplinkElementId}`);
    if (deeplinkElement) {
      deeplinkElement.addEventListener("click", this.handleOnClick);
    }

    window.addEventListener("blur", this.handleBlur);
  },

  destroyed() {
    if (this.handleBlur) {
      window.removeEventListener("blur", this.handleBlur);
    }

    const deeplinkElement = document.querySelector(`#${this.el.dataset.deeplinkElementId}`);
    if (this.handleOnClick && deeplinkElement) {
      document.querySelector(`#${this.el.dataset.deeplinkElementId}`).removeEventListener("click", this.handleOnClick);
    }
  },
};
