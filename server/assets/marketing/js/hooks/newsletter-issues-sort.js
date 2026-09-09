/*
 * Newsletter page: sorts the past-issues list in place.
 *
 * The rows arrive oldest first (issue #1 at the top, as in the comp). Each
 * click on the control flips the order by the rows' data-number, so the
 * page never round-trips. The button's label always names the order the
 * next click produces, and both it and the list carry data-direction so
 * the CSS can reflect the current state.
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

    const ascending = this.el.dataset.direction !== "ascending";
    const rows = Array.from(this.list.children);
    rows.sort((a, b) => {
      const difference = Number(a.dataset.number) - Number(b.dataset.number);
      return ascending ? difference : -difference;
    });
    this.list.append(...rows);

    const direction = ascending ? "ascending" : "descending";
    this.el.dataset.direction = direction;
    this.list.dataset.direction = direction;
    this.el.setAttribute("aria-label", ascending ? this.el.dataset.labelAscending : this.el.dataset.labelDescending);
  },
};
