/**
 * PricingRunnerMachineSelect Hook
 *
 * Drives one Tuist Runners price card on the pricing page. Its vCPU and
 * memory-per-vCPU pickers (Noora button groups) live in the toolbar above
 * the cards, in the element `data-controls` names; a pick resolves to a
 * machine from the card's `data-machines` list. The server renders each machine's
 * translated spec and formatted figures into that list, so a pick only
 * swaps text. The server also renders the default machine, so the panel
 * reads fine before this mounts.
 *
 * The price is an odometer (see lib/digit-reel.js): on a new pick its
 * digits roll up for a pricier machine and down for a cheaper one. The
 * reels are hidden from assistive tech; a visually hidden readout next to
 * them carries the plain text. The smaller figures just swap.
 */
import { setReel } from "../lib/digit-reel.js";

const FIGURES = ["price"];

export const PricingRunnerMachineSelect = {
  mounted() {
    this.machines = JSON.parse(this.el.dataset.machines);
    this.vcpus = Number(this.el.dataset.defaultVcpus);
    this.gb = Number(this.el.dataset.defaultGb);
    // The memory per vCPU the reader picked. It outlives sizes that don't
    // offer it: 4 GB/vCPU → 1 vCPU (2 GB only) → back up returns to 4 GB.
    this.preferredRatio = this.gb / this.vcpus;
    this.controls = document.getElementById(this.el.dataset.controls);
    if (!this.controls) {
      console.error("Pricing runner machine select: no controls found");
      return;
    }

    this.readouts = {};
    for (const field of FIGURES) {
      const figure = this.el.querySelector(`[data-machine-out="${field}"]`);
      if (!figure) continue;
      const readout = document.createElement("span");
      readout.className = "sr-only";
      figure.setAttribute("aria-hidden", "true");
      figure.after(readout);
      this.readouts[field] = readout;
    }

    this.onClick = (e) => {
      const vcpusItem = e.target.closest("[data-machine-vcpus]");
      const ratioItem = e.target.closest("[data-machine-ratio]");
      if (vcpusItem) {
        this.pick(Number(vcpusItem.dataset.machineVcpus));
      } else if (ratioItem && !ratioItem.disabled) {
        this.preferredRatio = Number(ratioItem.dataset.machineRatio);
        this.pick(this.vcpus);
      }
    };
    this.controls.addEventListener("click", this.onClick);

    this.render();
  },

  // Uses the preferred memory per vCPU when the size offers it, and falls
  // back to that size's first machine otherwise.
  pick(vcpus) {
    const machine =
      this.machines.find((m) => m.vcpus === vcpus && m.memory_gb === vcpus * this.preferredRatio) ||
      this.machines.find((m) => m.vcpus === vcpus);
    if (!machine) return;
    this.vcpus = machine.vcpus;
    this.gb = machine.memory_gb;
    this.render();
  },

  render() {
    const machine = this.machines.find((m) => m.vcpus === this.vcpus && m.memory_gb === this.gb);
    if (!machine) return;

    for (const field of ["spec", "hourly"]) {
      const out = this.el.querySelector(`[data-machine-out="${field}"]`);
      if (out) out.textContent = machine[field];
    }
    for (const field of FIGURES) {
      if (!this.readouts[field]) continue;
      this.readouts[field].textContent = machine[field];
      setReel(this.el.querySelector(`[data-machine-out="${field}"]`), machine[field]);
    }

    this.controls.querySelectorAll("[data-machine-vcpus]").forEach((item) => {
      const selected = Number(item.dataset.machineVcpus) === this.vcpus;
      item.toggleAttribute("data-selected", selected);
      item.setAttribute("aria-pressed", selected ? "true" : "false");
    });

    // 1 vCPU only comes with 2 GB, so the higher ratio is disabled there.
    this.controls.querySelectorAll("[data-machine-ratio]").forEach((item) => {
      const ratio = Number(item.dataset.machineRatio);
      const selected = ratio === this.gb / this.vcpus;
      item.toggleAttribute("data-selected", selected);
      item.setAttribute("aria-pressed", selected ? "true" : "false");
      item.disabled = !this.machines.some((m) => m.vcpus === this.vcpus && m.memory_gb === this.vcpus * ratio);
    });
  },

  destroyed() {
    this.controls?.removeEventListener("click", this.onClick);
  },
};
