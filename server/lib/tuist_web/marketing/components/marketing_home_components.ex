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
      <svg data-part="mark" viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path
          d="M14 28C13.987 27.9941 13.9747 27.9873 13.9616 27.976C13.6474 27.705 13.3807 24.5933 13.3075 24.0193C12.7908 19.7403 12.1308 15.4803 11.3288 11.2464C11.0425 9.74432 10.7479 8.24385 10.4451 6.74498C10.1864 5.45569 9.96718 4.28443 9.82802 2.97478C9.56263 0.477938 11.3874 0.136877 13.4518 0.0156154C13.6103 0.00678462 13.7958 0.000753846 14 0C14.2042 0.000753846 14.3897 0.00678462 14.5482 0.0156154C16.6126 0.136877 18.4375 0.477938 18.1721 2.97478C18.0328 4.28443 17.8136 5.45569 17.5549 6.74498C17.2522 8.24385 16.9575 9.74432 16.6712 11.2464C15.8692 15.4803 15.2092 19.7403 14.6925 24.0193C14.6193 24.5933 14.3526 27.705 14.0384 27.976C14.0253 27.9873 14.013 27.9941 14 28Z"
          fill="currentColor"
        />
        <path
          d="M6.08117 2.95702C7.03362 2.84189 7.48009 3.55654 7.80498 4.33375C8.13622 5.12572 8.40344 5.96874 8.65449 6.79065C8.96374 7.79488 9.25823 8.80363 9.53784 9.8168C10.8233 14.391 11.8864 19.0263 12.7233 23.7053C12.8517 24.4162 12.9759 25.1277 13.0959 25.8399C13.2057 26.4952 13.3296 27.2089 13.3366 27.8697C12.8655 27.5603 12.5927 26.7536 12.3653 26.235C12.1422 25.7282 11.9166 25.2229 11.6884 24.7187C11.4106 24.0492 11.0069 23.2362 10.6899 22.5822C9.12198 19.3449 7.26354 16.2592 5.13842 13.3644C4.54384 12.5493 3.92716 11.7507 3.28914 10.9699C2.72582 10.2672 1.92082 9.359 1.6245 8.52234C1.04448 6.88498 2.64012 5.19885 3.76321 4.21292C4.39498 3.65852 5.23759 3.09368 6.08117 2.95702Z"
          fill="currentColor"
        />
        <path
          d="M1.20692 11.805C1.4875 11.7833 1.76647 11.8967 1.99208 12.0577C2.55734 12.4611 3.08455 13.0048 3.55635 13.5097C7.03976 17.2376 9.68713 21.6799 11.9164 26.2621C12.1833 26.8111 12.4497 27.3713 12.6692 27.9408C12.3839 27.7999 12.1504 27.6459 11.8871 27.472C11.2045 27.0001 10.4699 26.4126 9.81325 25.8987C8.7585 25.0598 7.69363 24.2344 6.61872 23.4221C5.704 22.7362 4.78357 22.0586 3.85774 21.3884C2.12962 20.1364 0.900681 19.4396 0.321083 17.2054C-0.0136115 15.9155 -0.472051 12.2491 1.20692 11.805Z"
          fill="currentColor"
        />
        <path
          d="M26.7931 11.805C26.5125 11.7833 26.2335 11.8967 26.0079 12.0577C25.4427 12.4611 24.9155 13.0048 24.4436 13.5097C20.9602 17.2376 18.3129 21.6799 16.0836 26.2621C15.8167 26.8111 15.5503 27.3713 15.3308 27.9408C15.6161 27.7999 15.8496 27.6459 16.1129 27.472C16.7955 27.0001 17.5301 26.4126 18.1868 25.8987C19.2415 25.0598 20.3064 24.2344 21.3813 23.4221C22.296 22.7362 23.2164 22.0586 24.1423 21.3884C25.8704 20.1364 27.0993 19.4396 27.6789 17.2054C28.0136 15.9155 28.4721 12.2491 26.7931 11.805Z"
          fill="currentColor"
        />
        <path
          d="M21.9188 2.95702C20.9664 2.84189 20.5199 3.55654 20.195 4.33375C19.8638 5.12572 19.5966 5.96874 19.3455 6.79065C19.0363 7.79488 18.7418 8.80363 18.4622 9.8168C17.1767 14.391 16.1136 19.0263 15.2767 23.7053C15.1483 24.4162 15.0241 25.1277 14.9041 25.8399C14.7943 26.4952 14.6704 27.2089 14.6634 27.8697C15.1345 27.5603 15.4073 26.7536 15.6347 26.235C15.8578 25.7282 16.0834 25.2229 16.3116 24.7187C16.5894 24.0492 16.9931 23.2362 17.3101 22.5822C18.878 19.3449 20.7365 16.2592 22.8616 13.3644C23.4562 12.5493 24.0728 11.7507 24.7109 10.9699C25.2742 10.2672 26.0792 9.359 26.3755 8.52234C26.9555 6.88498 25.3599 5.19885 24.2368 4.21292C23.605 3.65852 22.7624 3.09368 21.9188 2.95702Z"
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
