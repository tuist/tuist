defmodule TuistWeb.Noora.Pages.Badge do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Badge",
    description: "Labels an item with a short status or category.",
    components: [{Noora.Badge, :badge}],
    guidelines: [
      "Keep labels to one or two words. A badge annotates something else and should not carry a sentence.",
      "Pick the color for its meaning, not for decoration: `success` for healthy or passing, `destructive` for failures, `warning` and `attention` for things that need a look.",
      "Use `light-fill` when several badges sit together, so the row stays calm. Save `fill` for the one that needs attention.",
      "For run and job states, use the status badge, which pairs each state with a consistent icon."
    ]

  example "Variants",
    description: "Each color comes as a solid `fill` and a softer `light-fill`. `neutral` is the default color.",
    layout: :rows do
    ~H"""
    <div :for={
      color <- ~w(neutral primary secondary information focus success attention warning destructive)
    }>
      <.badge size="large" label={String.capitalize(color)} color={color} />
      <.badge size="large" label={String.capitalize(color)} color={color} style="light-fill" />
    </div>
    """
  end

  # TEMPORARY: compares light-fill backgrounds on each surface. Remove with
  # blend_controls/1 below and the .noora-docs-badge-surfaces styles in
  # noora.css.
  example "Surfaces (temporary)",
    description:
      "Light-fill badges on each surface, before and after the new colors. Before is the 100 tint in light mode and the alpha token in dark mode; after is a tint multiplied (light) or screened (dark) onto the surface, tuned with the controls. The columns show each label's contrast in light and dark mode; values under 4.5:1 (WCAG AA) are red.",
    layout: :column do
    ~H"""
    <div class="noora-docs-badge-surfaces">
      <.blend_controls />
      <div data-part="surfaces">
        <div :for={surface <- ~w(primary tertiary secondary)} data-surface={surface}>
          <span data-part="surface-name">{String.capitalize(surface)} surface</span>
          <div
            :for={{approach, title} <- [{"current", "Before"}, {"blend", "After"}]}
            data-approach={approach}
            data-part="half"
          >
            <span data-part="half-title">{title}</span>
            <span data-part="mode-icon" title="Contrast in light mode"><.sun_high /></span>
            <span data-part="mode-icon" title="Contrast in dark mode"><.moon /></span>
            <div
              :for={
                color <-
                  ~w(neutral primary secondary information focus success attention warning destructive)
              }
              data-part="cell"
            >
              <.badge size="large" style="light-fill" color={color} label={String.capitalize(color)} />
              <span
                :for={mode <- ~w(light dark)}
                id={"badge-contrast-#{approach}-#{surface}-#{color}-#{mode}"}
                data-ratio={mode}
                phx-update="ignore"
              >
                –
              </span>
            </div>
          </div>
        </div>
      </div>
      <div data-part="sizes">
        <div data-part="sizes-header">
          <span data-part="surface-name">All sizes</span>
          <div
            id="badge-sizes-surface"
            data-part="surface-switch"
            role="radiogroup"
            aria-label="Surface"
            phx-update="ignore"
          >
            <label :for={surface <- ~w(primary tertiary secondary)}>
              <input
                type="radio"
                name="badge-sizes-surface"
                value={surface}
                checked={surface == "primary"}
              />
              <span>{String.capitalize(surface)}</span>
            </label>
          </div>
        </div>
        <div
          :for={{approach, title} <- [{"current", "Before"}, {"blend", "After"}]}
          data-approach={approach}
          data-part="sizes-half"
        >
          <span data-part="half-title">{title}</span>
          <span :for={size <- ~w(small medium large)} data-part="size-heading">
            {String.capitalize(size)}
          </span>
          <%= for color <- ~w(neutral primary secondary information focus success attention warning destructive) do %>
            <span :for={size <- ~w(small medium large)} data-part="size-cell">
              <.badge size={size} style="light-fill" color={color} label={String.capitalize(color)}>
                <:icon><.bell /></:icon>
              </.badge>
            </span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  example "With icons",
    description: "An icon before the label, in every color, style, and size.",
    layout: :rows do
    ~H"""
    <div :for={
      color <- ~w(neutral primary secondary information focus success attention warning destructive)
    }>
      <.badge
        :for={size <- ~w(large medium small)}
        label={String.capitalize(color)}
        color={color}
        size={size}
      >
        <:icon><.bell /></:icon>
      </.badge>
      <.badge
        :for={size <- ~w(small medium large)}
        label={String.capitalize(color)}
        color={color}
        style="light-fill"
        size={size}
      >
        <:icon><.bell /></:icon>
      </.badge>
    </div>
    """
  end

  example "Sizes",
    description: "Small is the default. Medium suits headers and cards with more room, and large suits page headers." do
    ~H"""
    <.badge label="Small" size="small" color="primary" />
    <.badge label="Medium" size="medium" color="primary" />
    <.badge label="Large" size="large" color="primary" />
    """
  end

  example "Dot and icon", description: "A dot or an icon before the label reinforces the status at a glance." do
    ~H"""
    <.badge size="large" label="Live" color="success" style="light-fill" dot />
    <.badge size="large" label="Flaky" color="warning" style="light-fill">
      <:icon><.alert_circle /></:icon>
    </.badge>
    """
  end

  example "Disabled", description: "Ignores the color and uses the disabled presentation." do
    ~H"""
    <.badge size="large" label="Disabled" color="success" disabled />
    """
  end

  # TEMPORARY: the controls for the blend approach in the "Surfaces" example,
  # and the live contrast check for every badge in the example. Each slider
  # sets a custom property on the demo that the blend tints read, and updates
  # its value in the formula. Each picker sets one color's label, or the token
  # its tint is built from, for one mode. The contrast check clones the
  # surfaces into hidden light and dark copies of the demo, reads their
  # resolved colors, and composites each background over its surface the way
  # the browser does: normally for Before, and with
  # multiply (light) or screen (dark) for the blend.
  defp blend_controls(assigns) do
    hue_steps = ~w(50 100 200 300 400 500 600 700 800 900 950)
    neutral_steps = ~w(50 100 200 300 400 500 600 700 800 900 1000 1100 1200)
    scale = fn prefix, steps -> Enum.map(steps, &"#{prefix}-#{&1}") end

    colors = [
      {"neutral", "neutral-light-1100", "neutral-light-200", "neutral-dark-50", "neutral-dark-1100"},
      {"primary", "purple-700", "purple-500", "purple-300", "purple-500"},
      {"secondary", "pink-700", "pink-900", "pink-300", "pink-500"},
      {"information", "azure-700", "azure-800", "azure-300", "azure-500"},
      {"focus", "blue-700", "blue-950", "blue-300", "blue-600"},
      {"success", "green-700", "green-500", "green-300", "green-600"},
      {"attention", "yellow-800", "yellow-400", "yellow-400", "yellow-500"},
      {"warning", "orange-700", "orange-800", "orange-300", "orange-400"},
      {"destructive", "red-700", "red-800", "red-300", "red-400"}
    ]

    tokens = fn
      "neutral", "light", _ ->
        scale.("neutral-light", neutral_steps)

      "neutral", "dark", :label ->
        scale.("neutral-dark", neutral_steps)

      "neutral", "dark", :background ->
        ~w(neutral-gray-16 neutral-gray-24 neutral-gray-50) ++ scale.("neutral-dark", neutral_steps)

      _color, _mode, _part ->
        nil
    end

    pickers = fn mode ->
      for {color, label_light, background_light, label_dark, background_dark} <- colors do
        {label, background} =
          if mode == "light", do: {label_light, background_light}, else: {label_dark, background_dark}

        hue_tokens = scale.(String.replace(label, ~r/-\d+$/, ""), hue_steps)

        {color, {label, "--noora-docs-label-#{mode}", tokens.(color, mode, :label) || hue_tokens},
         {background, "--noora-docs-badge-base-#{mode}", tokens.(color, mode, :background) || hue_tokens}}
      end
    end

    # The five major tick values under each slider: min, max, and the
    # quarters between.
    axis = fn min, max ->
      {min, _} = Float.parse(min)
      {max, _} = Float.parse(max)

      for i <- 0..4 do
        (min + (max - min) * i / 4) |> Float.round(3) |> to_string() |> String.replace_suffix(".0", "")
      end
    end

    assigns =
      assign(assigns,
        axis: axis,
        modes: [
          %{
            mode: "light",
            title: "Light",
            blend: "multiply",
            lightness: {"--noora-docs-blend-light-l", "0.8", "1", "0.005", "0.95"},
            chroma: {"--noora-docs-blend-light-c", "0", "2", "0.05", "0.5"},
            pickers: pickers.("light")
          },
          %{
            mode: "dark",
            title: "Dark",
            blend: "screen",
            lightness: {"--noora-docs-blend-dark-l", "0.1", "0.5", "0.005", "0.24"},
            chroma: {"--noora-docs-blend-dark-c", "0", "2", "0.05", "0.5"},
            pickers: pickers.("dark")
          }
        ]
      )

    ~H"""
    <div
      id="noora-docs-blend-controls"
      class="noora-docs-blend-controls"
      phx-hook=".NooraDocsBlendControls"
      phx-update="ignore"
    >
      <div :for={mode <- @modes} data-mode={mode.mode}>
        <div data-part="mode-header">
          <.sun_high :if={mode.mode == "light"} />
          <.moon :if={mode.mode == "dark"} />
          <span>{mode.title}</span>
          <code data-part="formula">{mode.blend}(oklch(<span data-live={elem(mode.lightness, 0)}>{elem(mode.lightness, 4)}</span>&nbsp;C×<span data-live={
            elem(mode.chroma, 0)
          }>{elem(mode.chroma, 4)}</span>&nbsp;H))</code>
        </div>
        <label
          :for={
            {label, {property, min, max, step, value}} <- [
              {"Lightness", mode.lightness},
              {"Chroma ×", mode.chroma}
            ]
          }
          data-part="slider"
        >
          <span>{label}</span>
          <output>{value}</output>
          <input
            type="range"
            min={min}
            max={max}
            step={step}
            value={value}
            data-property={property}
            data-default={value}
          />
          <span data-part="axis" aria-hidden="true">
            <span :for={tick <- @axis.(min, max)}>{tick}</span>
          </span>
        </label>
        <div data-part="pickers">
          <span data-part="column-heading">Color</span>
          <span data-part="column-heading">Label</span>
          <span data-part="column-heading">Background</span>
          <%= for {color, label, background} <- mode.pickers do %>
            <span>{String.capitalize(color)}</span>
            <select
              :for={
                {{default, property, options}, part} <- [{label, "label"}, {background, "background"}]
              }
              aria-label={"#{String.capitalize(color)} #{mode.mode} #{part}"}
              data-color={color}
              data-property={property}
              data-default={default}
            >
              <option :for={token <- options} value={token} selected={token == default}>
                {token}
              </option>
            </select>
          <% end %>
        </div>
      </div>
      <button type="button" data-part="reset">Reset</button>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".NooraDocsBlendControls">
      export default {
        mounted() {
          this.demo = this.el.closest(".noora-docs-badge-surfaces")
          const canvas = document.createElement("canvas")
          canvas.width = canvas.height = 1
          this.context = canvas.getContext("2d", { willReadFrequently: true })

          const slide = (input) => {
            const { property } = input.dataset
            this.demo.style.setProperty(property, input.value)
            input.closest("label").querySelector("output").textContent = input.value
            for (const live of this.el.querySelectorAll(`[data-live="${property}"]`)) {
              live.textContent = input.value
            }
          }
          const pick = (select) => {
            const { color, property } = select.dataset
            const badges = this.demo.querySelectorAll(
              `[data-approach="blend"] .noora-badge[data-style="light-fill"][data-color="${color}"]`
            )
            for (const badge of badges) {
              badge.style.setProperty(property, `var(--noora-${select.value})`)
            }
          }

          // The settings survive reloads (the dev server's live reload
          // included): they're saved in this browser and restored on mount.
          const STORAGE_KEY = "noora-docs-badge-blend-v2"
          const ranges = () => this.el.querySelectorAll("input[type=range]")
          const selects = () => this.el.querySelectorAll("select")
          const keyOf = (control) =>
            control.matches("select")
              ? `${control.dataset.color}:${control.dataset.property}`
              : control.dataset.property
          const save = () => {
            const state = {}
            for (const control of [...ranges(), ...selects()]) {
              if (control.value !== control.dataset.default) state[keyOf(control)] = control.value
            }
            try {
              localStorage.setItem(STORAGE_KEY, JSON.stringify(state))
            } catch (_error) {}
          }
          let saved = {}
          try {
            saved = JSON.parse(localStorage.getItem(STORAGE_KEY)) || {}
          } catch (_error) {}
          for (const input of ranges()) {
            if (keyOf(input) in saved) input.value = saved[keyOf(input)]
            slide(input)
          }
          for (const select of selects()) {
            if (keyOf(select) in saved) select.value = saved[keyOf(select)]
            pick(select)
          }

          this.el.addEventListener("input", (event) => {
            if (event.target.matches("input[type=range]")) slide(event.target)
            save()
            this.schedule()
          })
          this.el.addEventListener("change", (event) => {
            if (event.target.matches("select")) pick(event.target)
            save()
            this.schedule()
          })
          this.el.querySelector('[data-part="reset"]').addEventListener("click", () => {
            for (const input of ranges()) {
              input.value = input.dataset.default
              slide(input)
            }
            for (const select of selects()) {
              select.value = select.dataset.default
              pick(select)
            }
            try {
              localStorage.removeItem(STORAGE_KEY)
            } catch (_error) {}
            this.schedule()
          })
          this.schedule()
        },

        schedule() {
          cancelAnimationFrame(this.frame)
          this.frame = requestAnimationFrame(() => this.measure())
        },

        // Any CSS color, including oklch and alpha, as sRGB 0..1 plus alpha.
        rgba(color) {
          const context = this.context
          context.clearRect(0, 0, 1, 1)
          context.fillStyle = "#000"
          context.fillStyle = color
          context.fillRect(0, 0, 1, 1)
          const [r, g, b, a] = context.getImageData(0, 0, 1, 1).data
          return [r / 255, g / 255, b / 255, a / 255]
        },

        luminance([r, g, b]) {
          const linear = (v) => (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)
          return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        },

        measure() {
          // The surfaces are cloned into hidden light and dark copies; cells
          // pair up with their copies by order.
          const source = this.demo.querySelector('[data-part="surfaces"]')
          const cells = source.querySelectorAll('[data-part="cell"]')
          const probe = document.createElement("div")
          probe.setAttribute("aria-hidden", "true")
          probe.style.cssText =
            "position:absolute;width:0;height:0;overflow:hidden;visibility:hidden;pointer-events:none"
          const copies = {}
          for (const mode of ["light", "dark"]) {
            const scheme = document.createElement("div")
            scheme.style.colorScheme = mode
            const clone = source.cloneNode(true)
            for (const el of clone.querySelectorAll("[id]")) el.removeAttribute("id")
            scheme.append(clone)
            probe.append(scheme)
            copies[mode] = clone.querySelectorAll('[data-part="cell"]')
          }
          this.demo.append(probe)

          for (const mode of ["light", "dark"]) {
            copies[mode].forEach((copyCell, i) => {
              const blend = copyCell.closest("[data-approach]").dataset.approach === "blend"
              const badge = copyCell.querySelector(".noora-badge")
              const surface = this.rgba(getComputedStyle(copyCell.closest("[data-surface]")).backgroundColor)
              const fill = this.rgba(
                blend
                  ? getComputedStyle(badge, "::before").backgroundColor
                  : getComputedStyle(badge).backgroundColor
              )
              const mix = (cb, cs) => (!blend ? cs : mode === "light" ? cb * cs : cb + cs - cb * cs)
              const background = [0, 1, 2].map(
                (c) => fill[3] * mix(surface[c], fill[c]) + (1 - fill[3]) * surface[c]
              )
              const label = this.rgba(getComputedStyle(badge).color)
              const text = [0, 1, 2].map((c) => label[3] * label[c] + (1 - label[3]) * background[c])
              const [a, b] = [this.luminance(text), this.luminance(background)]
              const ratio = (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)

              const output = cells[i].querySelector(`[data-ratio="${mode}"]`)
              output.textContent = ratio.toFixed(2)
              output.toggleAttribute("data-fail", ratio < 4.5)
              output.title = `${ratio.toFixed(2)}:1 in ${mode} mode, ${ratio < 4.5 ? "below" : "meets"} WCAG AA`
            })
          }

          probe.remove()
        }
      }
    </script>
    """
  end
end
