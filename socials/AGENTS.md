# Socials

Image cards for Tuist's posts on X and LinkedIn, designed with Noora.
A card is an HTML page that loads Noora's own CSS from this repository
(`noora/css/tokens.css` plus the badge, tag and card component styles, through
`templates/base.css`) and the fonts the server ships, so cards follow the design
system as it changes. `render.mjs` turns a page into PNGs with headless Chrome.
Struo's cards live in the Struo repository (`tuist/struo`).

## Templates

Pick the template for the kind of announcement. Each one is a complete sample
card; copy it and replace the text.

| Template | Announces | Theme |
| --- | --- | --- |
| `templates/release.html` | A version of a Tuist product (CLI, Gradle plugin, app): date and product, version as the title, three highlights, install snippet | light; X and LinkedIn only |
| `templates/feature.html` | A new feature: heading, tag and badge, up to four "what / why" rows | light |
| `templates/metrics.html` | Before/after numbers as bars, such as a customer's build times | dark; X and LinkedIn only |

Every template switches theme with `data-theme="light"` or `"dark"` on `<html>`.
A template that only works as a rectangle says so with
`<meta name="card-sizes" content="x,linkedin">`; `render.mjs` then renders only
those sizes and refuses the others.

For a release, keep exactly three highlights: two or three words of title and
a description of about 40 characters each, covering what users can do now.
Take them from the release notes or `server/priv/marketing/changelog`, and show
the product's real install line (the `mise` command for the CLI, the
`plugins { }` line for Gradle).

When an announcement fits none of them, follow [GUIDELINES.md](GUIDELINES.md):
what to keep, what may change, and what to avoid when deviating.

## Making a card

1. Copy the template into `cards/`, named for the post:
   `mkdir -p socials/cards && cp socials/templates/release.html socials/cards/gradle-coverage.html`.
   Relative paths work from any directory one level below `socials/`.
2. Replace the text. Write it like the post: short, concrete, no marketing filler.
   Use real figures only, with their source. Keep a heading to one line at X size.
3. Render: `node socials/render.mjs socials/cards/<name>.html` (every size) or add
   `--size x`, `linkedin` or `square`.
4. Look at every PNG in `socials/out/` before handing it over; check for clipping,
   wrapping and empty space. The square size has the most spare height.

Never post, upload or schedule a card: hand the PNGs to a person.

| `--size` | CSS viewport | PNG (2x) | Where |
| --- | --- | --- | --- |
| `x` | 1200×675 | 2400×1350 | X timeline (16:9) |
| `linkedin` | 1200×627 | 2400×1254 | LinkedIn landscape (1.91:1) |
| `square` | 1080×1080 | 2160×2160 | Either network |

`render.mjs` needs Node.js and Chrome or Chromium; it looks in the usual macOS
and Linux locations and agent-browser's download, or takes `CHROME=/path/to/chrome`.
`cards/` and `out/` are for working copies; `out/` is ignored by Git.

## Adding a template

- Follow [GUIDELINES.md](GUIDELINES.md). Start from an existing template and link
  `../templates/base.css`.
- Use Noora tokens (`--noora-surface-*`, `--noora-chart-*`, `--noora-font-*`,
  `--noora-border-*`) instead of raw colors and fonts.
- Reuse Noora component markup (`.noora-badge`, `.noora-tag`) inside a `.scaled`
  wrapper, which shows dashboard-sized components at card size.
- Lay out with flexbox so one page fits every size, and verify all three renders.
- Take logos from `server/priv/static/marketing/images/brand/`.
- Add the template to the table above with the kind of announcement it serves.
