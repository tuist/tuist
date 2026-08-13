defmodule TuistWeb.Marketing.MarketingHomeComponents do
  @moduledoc ~S"""
  A collection of components that are used in the marketing home page.
  """
  use TuistWeb, :live_component

  import TuistWeb.Marketing.MarketingComponents

  embed_templates "marketing_home_components/*"

  attr :testimonials, :list, required: true
  attr :rest, :global

  def testimonial_marquee_row(assigns) do
    ~H"""
    <div data-part="row" style={"--marquee-card-count: #{length(@testimonials)}"} {@rest}>
      <div data-part="track">
        <%!-- Two identical groups; the track scrolls one group's width per
            loop, so the hand-off is seamless. --%>
        <div :for={duplicate? <- [false, true]} data-part="group" aria-hidden={duplicate?}>
          <article :for={testimonial <- @testimonials} data-part="card">
            <blockquote data-part="quote">“{testimonial.quote}”</blockquote>
            <div data-part="author">
              <img
                data-part="avatar"
                src={testimonial.avatar_src}
                alt={testimonial.name}
                loading="lazy"
              />
              <div data-part="identity">
                <span data-part="name">{testimonial.name}</span>
                <span data-part="role">{testimonial.role}</span>
              </div>
            </div>
          </article>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :cta_variant, :string, required: false, default: "light"
  attr :cta_href, :string, required: false
  attr :cta_target, :string, default: ""
  attr :cta_text, :string, required: false

  def highlight_card(assigns) do
    ~H"""
    <div class="marketing__home__section__highlights__item">
      <div class="marketing__home__section__highlights__item__main">
        <h3 class="font-xxl-strong marketing__home__section__highlights__item__main__title">
          {@title}
        </h3>
        <p class="font-m marketing__home__section__highlights__item__main__subtitle">
          {@subtitle}
        </p>
      </div>
      <div
        :if={not is_nil(Map.get(assigns, :cta_text))}
        class="marketing__home__section__highlights__item__footer"
      >
        <.secondary_button
          :if={not is_nil(Map.get(assigns, :cta_text))}
          size="medium"
          variant={@cta_variant}
          target={@cta_target}
          href={@cta_href}
        >
          {raw(@cta_text)}
        </.secondary_button>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :description, :string, required: true
  attr :requires_projects, :boolean, default: false
  attr :id, :string, required: true
  attr :traits, :list, default: []
  slot :inner_block, required: false
  slot :logo, required: true

  def feature(assigns) do
    ~H"""
    <section class="marketing__home__section__features__feature" id={@id}>
      <div class="marketing__home__section__features__feature__side">
        {render_slot(@logo, %{class: "marketing__home__section__features__feature__side__logo"})}
      </div>
      <div class="marketing__home__section__features__feature__main">
        <h3 class="marketing__home__section__features__feature__title">
          {render_slot(@logo, %{class: "marketing__home__section__features__feature__title__logo"})}
          <span>{@name}</span>
          <%= if @requires_projects do %>
            <span class="marketing__home__section__features__feature__title__badge">
              {dgettext("marketing", "Requires a generated project")}
            </span>
          <% end %>
        </h3>
        <p class="marketing__home__section__features__feature__description">
          {@description}
        </p>
        <div class="marketing__home__section__features__feature__traits">
          <div
            :for={trait <- @traits}
            class="marketing__home__section__features__feature__traits__trait"
          >
            <TuistWeb.Marketing.MarketingIcons.check_circle_icon
              size={32}
              class="marketing__home__section__features__feature__traits__trait__icon"
            />
            <span>
              {trait}
            </span>
          </div>
        </div>
        <div class="marketing__home__section__features__feature__main">
          {render_slot(@inner_block)}
        </div>
        <div class="marketing__home__section__features__feature__main__divider" />
      </div>
    </section>
    """
  end

  slot :inner_block, required: true
  attr :terminal_id, :string, required: true
  attr :rest, :global

  def terminal(assigns) do
    ~H"""
    <div class="marketing__home__terminal" {@rest}>
      <div class="marketing__home__terminal__bar">
        <div class="marketing__home__terminal__bar__close_button" />
        <div class="marketing__home__terminal__bar__minimize_button" />
        <div class="marketing__home__terminal__bar__maximize_button" />
      </div>
      <div class="marketing__home__terminal__main">
        <div class="font-mono marketing__home__terminal__main__prompt" id={@terminal_id}>
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  # Blueprint-style decoration panels drawn around the home hero. The
  # geometry is absolute coordinates on a fixed 1497x496 stage.
  # Panels with `h: :fill` pin to the stage bottom
  # instead of a fixed height, so the canvas' bottom edge always tracks the
  # hero card's actual height (uniform 64px padding, locale-dependent copy). On wider viewports the stage grows to the full
  # viewport width: panels tagged edge: :left/:right (the ones that touch the
  # stage's 2px inset) pin to the screen edges and stretch, everything else
  # stays centered with the hero. On narrower viewports the composition is
  # cropped symmetrically (never reflowed).
  @platform_panels [
    %{name: "A1", x: 102, y: 181, w: 145.5, h: :fill, edge: nil},
    %{name: "A2", x: 102, y: 97, w: 145.5, h: 82, edge: nil},
    %{name: "A3", x: 2, y: 305, w: 98, h: :fill, edge: :left},
    %{name: "A4", x: 2, y: 273, w: 98, h: 30, edge: :left},
    %{name: "A5", x: 2, y: 97, w: 98, h: 174, edge: :left},
    %{name: "A6", x: 67, y: 0, w: 180.5, h: 95, edge: nil},
    %{name: "A7", x: 249.5, y: 0, w: 156, h: 95, edge: nil},
    %{name: "A8", x: 407.5, y: 0, w: 94, h: 95, edge: nil},
    %{name: "A9", x: 503.5, y: 0, w: 24, h: 95, edge: nil},
    %{name: "A10", x: 529.5, y: 0, w: 252, h: 95, edge: nil},
    %{name: "A11", x: 783.5, y: 0, w: 252, h: 95, edge: nil},
    %{name: "A12", x: 1037.5, y: 0, w: 210, h: 95, edge: nil},
    %{name: "A13", x: 1249.5, y: 0, w: 115, h: 95, edge: nil},
    %{name: "A14", x: 1366.5, y: 0, w: 128.5, h: 95, edge: :right},
    %{name: "A15", x: 1249.5, y: 97, w: 180, h: 150, edge: nil},
    %{name: "A16", x: 1249.5, y: 249, w: 100, h: 100, edge: nil},
    %{name: "A17", x: 1249.5, y: 351, w: 203.5, h: :fill, edge: nil},
    %{name: "A18", x: 1351.5, y: 249, w: 143.5, h: 100, edge: :right},
    %{name: "A19", x: 1431.5, y: 97, w: 63.5, h: 150, edge: :right},
    %{name: "A20", x: 1455, y: 351, w: 40, h: :fill, edge: :right},
    %{name: "A21", x: 2, y: 0, w: 63, h: 95, edge: :left}
  ]

  @kura_lit [3, 9, 17, 24]

  def platform_hero_panels(assigns) do
    assigns = assign(assigns, :panels, @platform_panels)

    ~H"""
    <div data-part="panels" aria-hidden="true">
      <div
        :for={panel <- @panels}
        data-part="panel"
        data-name={panel.name}
        data-edge={panel.edge}
        style={panel_style(panel)}
      >
        <.platform_widget name={panel.name} />
      </div>
    </div>
    """
  end

  defp panel_style(%{h: :fill} = panel) do
    "--panel-x: #{panel.x}px; --panel-w: #{panel.w}px; top: #{panel.y}px; bottom: 0;"
  end

  defp panel_style(panel) do
    "--panel-x: #{panel.x}px; --panel-w: #{panel.w}px; top: #{panel.y}px; height: #{panel.h}px;"
  end

  attr :name, :string, required: true

  defp platform_widget(%{name: "A5"} = assigns) do
    ~H"""
    <div data-part="widget" data-widget="cache-hit">
      <span data-part="label">CACHE HIT %</span>
      <svg data-part="graph" viewBox="0 0 98 174" preserveAspectRatio="none">
        <path data-part="line" fill="none"></path>
      </svg>
    </div>
    """
  end

  defp platform_widget(%{name: "A6"} = assigns) do
    ~H"""
    <div data-part="widget" data-widget="vlines"></div>
    """
  end

  defp platform_widget(%{name: "A7"} = assigns) do
    ~H"""
    <div data-part="widget" data-widget="all-systems">
      <div data-part="bars">
        <span></span>
        <span></span>
        <span></span>
      </div>
      <span data-part="label">ALL SYSTEMS NORMAL</span>
    </div>
    """
  end

  defp platform_widget(%{name: "A14"} = assigns) do
    ~H"""
    <div data-part="widget" data-widget="auth">
      <span data-part="label">AUTH</span>
      <span data-part="toggle"><span data-part="knob"></span></span>
    </div>
    """
  end

  defp platform_widget(%{name: "A15"} = assigns) do
    rows =
      [5, 8, 8, 8]
      |> Enum.map_reduce(0, fn count, offset ->
        {Enum.map(offset..(offset + count - 1), &(&1 in @kura_lit)), offset + count}
      end)
      |> elem(0)

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <div data-part="widget" data-widget="kura-nodes">
      <span data-part="label">CACHE NODES</span>
      <div data-part="circles">
        <div :for={row <- @rows} data-part="row">
          <span :for={lit <- row} data-lit={to_string(lit)}></span>
        </div>
      </div>
    </div>
    """
  end

  defp platform_widget(%{name: "A17"} = assigns) do
    ~H"""
    <div data-part="widget" data-widget="oos">
      <div data-part="words">
        <span>OPTIMIZE</span>
        <span>OBSERVE</span>
        <span>SHIP</span>
      </div>
      <svg data-part="mark" viewBox="0 0 14 14" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path
          d="M13.2791 9.80563C12.5437 10.3484 11.7582 10.8196 10.9326 11.1888C12.1777 9.77513 13.1738 8.07569 13.9336 6.50025C13.6952 6.03352 13.3943 5.58954 13.0646 5.18455C12.2986 6.6345 11.4104 8.03995 10.3307 9.2814C10.2 9.42864 10.0667 9.57514 9.93048 9.71988C10.7492 7.38072 11.2527 4.95831 11.6384 2.5329C11.2477 2.25016 10.8285 2.00167 10.3847 1.79318C9.98729 3.72886 9.49364 5.64654 8.86226 7.50122C8.58703 8.30469 8.28301 9.09666 7.93696 9.85513L7.69753 0.0302489C7.4677 0.00999965 7.23528 0 7.00026 0C6.76524 0 6.53281 0.00974966 6.30298 0.0302489L6.06329 9.85813C5.7131 9.09366 5.4166 8.29994 5.138 7.50147C4.50661 5.64654 4.01297 3.72886 3.61556 1.79343C3.17172 2.00192 2.75253 2.25041 2.36187 2.53315C2.74786 4.96031 3.25188 7.38472 4.07159 9.72538C3.93515 9.58014 3.80104 9.43239 3.66952 9.28165C2.59014 8.04019 1.70169 6.63475 0.935668 5.1848C0.605188 5.59054 0.30428 6.03527 0.0658885 6.50225C0.318547 7.03098 0.588327 7.55296 0.879118 8.06794C1.49857 9.1234 2.21894 10.2164 3.07211 11.1913C2.24462 10.8216 1.45759 10.3496 0.720882 9.80563C0.444617 10.1764 0.202594 10.5721 0 10.9901C3.7463 15.0029 10.2529 15.0037 14 10.9901C13.7971 10.5721 13.5554 10.1764 13.2791 9.80563Z"
          fill="currentColor"
        />
      </svg>
    </div>
    """
  end

  defp platform_widget(assigns) do
    ~H""
  end
end
