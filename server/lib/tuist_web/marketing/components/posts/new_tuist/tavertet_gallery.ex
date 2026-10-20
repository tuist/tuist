defmodule TuistWeb.Marketing.Components.Posts.NewTuist.TavertetGallery do
  @moduledoc """
  Mosaic gallery of photos from the founders' offsite in Tavertet, Spain. Two
  landscape shots frame two portrait shots on wide viewports; the tiles stack
  into a single column on narrow ones. Purely presentational.
  """
  use TuistWeb, :live_component

  @tiles [
    %{
      slot: "group",
      src: "/marketing/images/blog/2026/09/12/tavertet/group.jpg",
      alt: "The four of us on a mountain road above Tavertet at sunset"
    },
    %{
      slot: "portrait",
      src: "/marketing/images/blog/2026/09/12/tavertet/portrait.jpg",
      alt: "Marek looking back over the Catalan pre-Pyrenees"
    },
    %{
      slot: "sunset",
      src: "/marketing/images/blog/2026/09/12/tavertet/sunset.jpg",
      alt: "Pedro watching the sun drop behind the hills"
    },
    %{
      slot: "road",
      src: "/marketing/images/blog/2026/09/12/tavertet/road.jpg",
      alt: "Asmit walking a quiet mountain road on the way down"
    }
  ]

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(:tiles, @tiles)}
  end

  def render(assigns) do
    ~H"""
    <style :type={TuistWeb.ColocatedCSS}>
      [data-part="tavertet-gallery"] {
        display: block;
        box-sizing: border-box;
        margin: var(--noora-spacing-8) 0;
        width: 100%;
        max-width: 100%;

        & [data-part="mosaic"] {
          display: grid;
          gap: var(--noora-spacing-3);
          grid-template-columns: 1fr;
          grid-auto-rows: minmax(220px, auto);
        }

        @media (min-width: 640px) {
          & [data-part="mosaic"] {
            grid-template-columns: repeat(3, 1fr);
            grid-template-rows: repeat(2, minmax(180px, 1fr));
            grid-template-areas:
              "group    group    portrait"
              "sunset   road     portrait";
          }

          & [data-slot="group"]    { grid-area: group;    }
          & [data-slot="portrait"] { grid-area: portrait; }
          & [data-slot="sunset"]   { grid-area: sunset;   }
          & [data-slot="road"]     { grid-area: road;     }
        }

        & figure {
          margin: 0;
          border-radius: var(--noora-radius-4);
          overflow: hidden;
          background: var(--noora-surface-background-tertiary);
        }

        & figure img {
          display: block;
          width: 100% !important;
          height: 100% !important;
          max-width: 100% !important;
          object-fit: cover;
          margin: 0 !important;
          border-radius: 0 !important;
          box-shadow: none !important;
        }
      }
    </style>

    <div id={@id} data-part="tavertet-gallery">
      <div data-part="mosaic">
        <figure :for={tile <- @tiles} data-slot={tile.slot}>
          <img src={tile.src} alt={tile.alt} loading="lazy" />
        </figure>
      </div>
    </div>
    """
  end
end
