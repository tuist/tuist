export class Component {
  /**
   * @param {HTMLElement} el - The DOM element
   * @param {*} context - The context for the component
   */
  constructor(el, context) {
    if (!el || !(el instanceof HTMLElement)) {
      throw new Error("Component requires an HTMLElement");
    }

    this.el = el;
    this.service = this.initService(context);
    this.api = this.initApi();
  }

  /**
   * Initialize the service - Must be implemented by child classes
   * @param {*} context
   */
  initService(_context) {
    throw new Error("initService must be implemented by child class");
  }

  /**
   * Initialize the API - Must be implemented by child classes
   */
  initApi() {
    throw new Error("initApi must be implemented by child class");
  }

  /**
   * Render method - Must be implemented by child classes
   */
  render() {
    throw new Error("render must be implemented by child class");
  }

  /**
   * Initialize the component
   */
  init = () => {
    this.render();
    this.service.subscribe(() => {
      this.api = this.initApi();
      this.render();
    });
    this.service.start();
  };

  /**
   * Cleanup the component
   */
  destroy = () => {
    this.service.stop();
  };
}
