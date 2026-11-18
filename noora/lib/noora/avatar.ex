defmodule Noora.Avatar do
  @moduledoc """
  A component for rendering an avatar image or initials if an image is not available.

  ## Example

  ```elixir
  <.avatar id="user-1" name="John Doe" color="blue" size="medium" />
  ```
  """

  use Phoenix.Component

  attr(:id, :string, required: true, doc: "The unique identifier for the avatar.")

  attr(:name, :string,
    required: true,
    doc: "The name of the account to render the avatar for."
  )

  attr(:color, :string,
    values: ~w(gray red orange yellow green azure blue purple pink),
    default: "purple",
    doc: "The color of the avatar."
  )

  attr(:image_href, :string, default: nil, doc: "The URL of the image to render as the avatar.")

  attr(:image_alt, :string,
    default: nil,
    doc:
      "Alternative text for the avatar image. Pass an empty string where the person's name is already rendered beside the avatar, so assistive technology does not announce it twice. Leave unset for avatar-only controls, which still need an accessible name of their own."
  )

  attr(:image_decoding, :string,
    values: ~w(sync async auto),
    default: "async",
    doc: "The image decoding strategy to use when rendering an avatar image."
  )

  attr(:image_loading, :string,
    default: nil,
    doc: "The loading strategy to use when rendering an avatar image."
  )

  attr(:fallback, :string,
    values: ~w(initials placeholder),
    default: "initials",
    doc: "Determines the fallback for when an image is not available. Can be either initials or a placeholder image"
  )

  attr(:on_status_change, :string,
    default: nil,
    doc: "Event handler for when the status of the avatar changes."
  )

  attr(:size, :string,
    values: ~w(2xsmall small medium large xlarge 2xlarge),
    default: "medium",
    doc: "The size of the avatar. Defaults to medium."
  )

  attr(:rest, :global)

  def avatar(assigns) do
    number_of_initials =
      case assigns[:size] do
        "2xsmall" -> 1
        "xsmall" -> 1
        "small" -> 2
        "medium" -> 2
        "large" -> 2
        "xlarge" -> 2
        "2xlarge" -> 2
      end

    assigns = assign(assigns, :number_of_initials, number_of_initials)

    ~H"""
    <div
      class="noora-avatar"
      data-scope="avatar"
      id={@id}
      phx-hook="NooraAvatar"
      data-on-status-change={@on_status_change}
      data-size={@size}
      data-color={@color}
      {@rest}
    >
      <img
        :if={@image_href}
        data-part="image"
        src={@image_href}
        alt={@image_alt}
        decoding={@image_decoding}
        loading={@image_loading}
      />
      <.fallback_image
        :if={@fallback == "placeholder"}
        class="noora-avatar__fallback-image"
        data-part="fallback"
      />
      <span :if={@fallback == "initials"} data-part="initials">
        {@name
        |> String.split(~r/[\s,_\-]/)
        |> Enum.reject(&(&1 == ""))
        |> Enum.take(@number_of_initials)
        |> Enum.map(&String.first/1)
        |> Enum.map(&String.upcase/1)
        |> Enum.join()}
      </span>
    </div>
    """
  end

  attr(:class, :string, default: "")
  attr(:rest, :global)

  # An animated dither texture: four layers of dots, each revealed by a band
  # that drifts across the avatar at a different threshold, so where the
  # bands overlap the dots are denser. Styled and animated in avatar.css.
  defp fallback_image(assigns) do
    ~H"""
    <span class={@class} aria-hidden="true" {@rest}>
      <span :for={_layer <- 1..4} data-part="dither"></span>
    </span>
    """
  end
end
