/*
 * Newsletter page: sorts the past-issues list in place.
 *
 * The rows arrive newest first (the latest issue at the top). Each
 * click on the control flips the order by the rows' data-number, so the
 * page never round-trips. The button's label always names the order the
 * next click produces; the list carries data-direction for styling and
 * the button carries the same value as data-state, which Noora's icon
 * transition watches to morph between the two sort glyphs.
 */
export const NewsletterIssuesSort = {
  mounted() {
    this.list = document.getElementById(this.el.dataset.target);
    this.onClick = () => this.toggle();
    this.el.addEventListener("click", this.onClick);
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick);
  },

  toggle() {
    if (!this.list) return;

    const ascending = this.el.dataset.state !== "ascending";
    const rows = Array.from(this.list.children);
    rows.sort((a, b) => {
      const difference = Number(a.dataset.number) - Number(b.dataset.number);
      return ascending ? difference : -difference;
    });
    this.list.append(...rows);

    const direction = ascending ? "ascending" : "descending";
    this.el.dataset.state = direction;
    this.list.dataset.direction = direction;
    this.el.setAttribute("aria-label", ascending ? this.el.dataset.labelAscending : this.el.dataset.labelDescending);
  },
};
