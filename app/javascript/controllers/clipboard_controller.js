import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  static targets = ['success'];
  static values = {
    token: String,
  };

  async copy() {
    try {
      await window.navigator.clipboard.writeText(this.tokenValue);
      this.successTarget.textContent = `Token successfully copied to clipboard!`;
    } catch {
      this.successTarget.textContent = `We couldn't copy the token to your clipboard.`;
    }
  }
}
