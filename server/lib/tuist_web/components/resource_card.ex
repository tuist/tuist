defmodule TuistWeb.Components.ResourceCard do
  @moduledoc """
  Shared decorative background for project-style resource cards.
  """
  use Phoenix.Component

  attr(:id, :string, default: nil, doc: "Stable identifier used to namespace SVG definitions.")

  def background(assigns) do
    unique_id = assigns.id || UUIDv7.generate()

    assigns =
      assigns
      |> assign(:mask_id, "mask0_#{unique_id}")
      |> assign(:radial_gradient_id, "paint0_radial_#{unique_id}")

    ~H"""
    <svg
      id={@id}
      class="tuist-resource-card-background"
      viewBox="0 0 292 196"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      data-part="background"
      aria-hidden="true"
      focusable="false"
    >
      <mask
        id={@mask_id}
        style="mask-type:alpha"
        maskUnits="userSpaceOnUse"
        x="0"
        y="-1"
        width="292"
        height="198"
      >
        <rect
          x="0.5"
          y="-0.5"
          width="291"
          height="197"
          fill={"url(##{@radial_gradient_id})"}
          fill-opacity="0.2"
        />
      </mask>
      <g mask={"url(##{@mask_id})"}>
        <path d="M11 149.75H281" />
        <path d="M11 98H281" />
        <path d="M11 46.25H281" />
        <path d="M197.751 233V-37" />
        <path d="M146 233V-37" />
        <path d="M94.2501 233V-37" />
        <path d="M281 233L11 -37" />
        <path d="M11 233L281 -37" />
        <rect x="29" y="-19" width="234" height="234" />
        <circle cx="146" cy="98" r="51.75" />
        <circle cx="146" cy="98" r="74.25" />
        <circle cx="146" cy="98" r="117" />
      </g>
      <defs>
        <radialGradient
          id={@radial_gradient_id}
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(146 98) rotate(90) scale(99 146)"
        >
          <stop stop-color="white" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
      </defs>
    </svg>
    """
  end
end
