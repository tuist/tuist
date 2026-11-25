# Card guidelines

Use these when a post needs something the templates don't cover: another layout,
a screenshot, a diagram, an unusual number of rows. Deviate in layout and content;
keep the parts below that make a card recognizably Tuist's.

## Keep

- **Noora, not raw values.** Colors, type and borders come from Noora tokens
  (`--noora-surface-*`, `--noora-chart-*`, `--noora-font-*`, `--noora-border-*`)
  through `templates/base.css`. If a token is missing, propose it in Noora rather
  than hard-coding a color in one card.
- **The logo.** The Tuist wordmark from `server/priv/static/marketing/images/brand/`
  (the `-dark` file on dark cards), top-left, 40px high, untouched.
- **Type.** Inter for text, Geist Mono for numbers, code and units.
  - Heading: medium weight, 60–84px, tracking about -0.035em, one or two lines.
    A quieter second part goes in `--noora-surface-label-tertiary` at regular
    weight ("Code coverage *for Gradle*").
  - Body: 22–28px, `--noora-surface-label-secondary`.
  - Nothing under 20px (CSS); X and LinkedIn show cards small.
- **One accent.** Purple (`--noora-chart-primary`) marks the Tuist side, the new
  thing or the result. Comparisons put the other side in neutral grey. Green and
  red badges only for real good/bad outcomes.
- **Margins.** About 56px top and bottom, 72px left and right, at every size.
- **Real content.** Real product names, real figures with a source, real UI.
  Screenshots come from the dashboard or app, not mockups.

## Free to change

- Layout, as long as it fits the sizes the card declares. Charts, tables and
  changelog layouts are rectangles (`x`, `linkedin`); only use `square` for a
  card that fills it.
- Light or dark theme. Light reads as product and changelog; dark as
  announcements and results.
- Noora components on the card: badges, tags, cards, chart colors. Show them
  through the `.scaled` wrapper so they keep their proportions.
- Screenshots, inside a Noora card section (`--noora-border-section`, 24px radius)
  so they sit on the card rather than float.

## Avoid

- Gradients, glows, stock imagery, 3D, emoji in the image.
- More than one heading, or a heading that repeats the post's text word for word.
- Dense text: if a card needs more than about 30 words, the post or a thread should carry them.
- Mixing in Struo's look (dark, orange, Geist Mono). Struo's cards live in the
  Struo repository.

## When a deviation repeats

If the same kind of card is made a second time, turn it into a template in
`templates/` and add it to the table in `AGENTS.md`.
