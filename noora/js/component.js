export class Component {
  constructor(el, props) {
    if (!el) throw new Error("Root element not found");
    this.el = el;
    this.machine = this.initMachine(props);
    this.api = this.initApi();
  }

  init = () => {
    this.render();
    this.machine.subscribe(() => {
      this.api = this.initApi();
      this.render();
    });
    this.machine.start();
  };

  destroy = () => {
    this.machine.stop();
  };

  initMachine(_props) {
    throw new Error("Method 'initMachine' must be implemented.");
  }

  initApi() {
    throw new Error("Method 'initApi' must be implemented.");
  }

  render() {
    throw new Error("Method 'render' must be implemented.");
  }
}
