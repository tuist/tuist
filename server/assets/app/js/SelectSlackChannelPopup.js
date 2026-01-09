const SelectSlackChannelPopup = {
  mounted() {
    this.popup = null;
    this.channel = new BroadcastChannel("oauth_popup");
    this.nonce = null;

    this.channel.onmessage = (event) => {
      if (event.data && event.data.type === "oauth_complete" && event.data.success) {
        if (event.data.nonce && event.data.nonce !== this.nonce) {
          return;
        }
        if (this.popup && !this.popup.closed) {
          this.popup.close();
        }
        const eventName = this.el.dataset.event || "oauth_channel_selected";
        const payload = {};
        if (this.el.dataset.id) {
          payload.id = this.el.dataset.id;
        }
        if (event.data.channel_id) {
          payload.channel_id = event.data.channel_id;
        }
        if (event.data.channel_name) {
          payload.channel_name = event.data.channel_name;
        }
        this.pushEvent(eventName, payload);
      }
    };

    this.el.addEventListener("click", (e) => {
      e.preventDefault();
      const url = this.el.getAttribute("href") || this.el.dataset.url;
      const width = 600;
      const height = 700;
      const left = window.screenX + (window.outerWidth - width) / 2;
      const top = window.screenY + (window.outerHeight - height) / 2;
      this.nonce = crypto.randomUUID();
      sessionStorage.setItem("slack_popup_nonce", this.nonce);
      this.popup = window.open(url, "oauth_popup", `width=${width},height=${height},left=${left},top=${top},popup=1`);
    });
  },

  destroyed() {
    this.channel.close();
    if (this.popup && !this.popup.closed) {
      this.popup.close();
    }
  },
};

export default SelectSlackChannelPopup;
