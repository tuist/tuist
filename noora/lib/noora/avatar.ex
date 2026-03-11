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
    values: ~w(gray red orange yellow azure blue purple pink),
    default: "pink",
    doc: "The color of the avatar."
  )

  attr(:image_href, :string, default: nil, doc: "The URL of the image to render as the avatar.")

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
    values: ~w(2xsmall small medium large 2xlarge),
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
      <img :if={@image_href} data-part="image" src={@image_href} />
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

  defp fallback_image(assigns) do
    ~H"""
    <svg
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      data-part="fallback"
      class={@class}
      {@rest}
    >
      <path
        d="M0 6.4C0 4.15979 0 3.03969 0.435974 2.18404C0.819467 1.43139 1.43139 0.819467 2.18404 0.435974C3.03969 0 4.15979 0 6.4 0H17.6C19.8402 0 20.9603 0 21.816 0.435974C22.5686 0.819467 23.1805 1.43139 23.564 2.18404C24 3.03969 24 4.15979 24 6.4V17.6C24 19.8402 24 20.9603 23.564 21.816C23.1805 22.5686 22.5686 23.1805 21.816 23.564C20.9603 24 19.8402 24 17.6 24H6.4C4.15979 24 3.03969 24 2.18404 23.564C1.43139 23.1805 0.819467 22.5686 0.435974 21.816C0 20.9603 0 19.8402 0 17.6V6.4Z"
        data-part="fallback-image-background"
      />
      <path
        fill-rule="evenodd"
        clip-rule="evenodd"
        d="M9 8C8.73478 8 8.48043 8.10536 8.29289 8.29289C8.10536 8.48043 8 8.73478 8 9V12.7929L9.64645 11.1464L9.65331 11.1397C9.96038 10.8442 10.3386 10.6651 10.75 10.6651C11.1614 10.6651 11.5396 10.8442 11.8467 11.1397L11.8536 11.1464L13 12.2929L13.1464 12.1464L13.1533 12.1397C13.4604 11.8442 13.8386 11.6651 14.25 11.6651C14.6614 11.6651 15.0396 11.8442 15.3467 12.1397L15.3536 12.1464L16 12.7929V9C16 8.73478 15.8946 8.48043 15.7071 8.29289C15.5196 8.10536 15.2652 8 15 8H9ZM17 13.9995V9C17 8.46957 16.7893 7.96086 16.4142 7.58579C16.0391 7.21071 15.5304 7 15 7H9C8.46957 7 7.96086 7.21071 7.58579 7.58579C7.21071 7.96086 7 8.46957 7 9V13.9999C7 13.9999 7 14 7 13.9999V15C7 15.5304 7.21071 16.0391 7.58579 16.4142C7.96086 16.7893 8.46957 17 9 17H15C15.5304 17 16.0391 16.7893 16.4142 16.4142C16.7893 16.0391 17 15.5304 17 15V14.0005C17 14.0002 17 13.9998 17 13.9995ZM16 14.2071L14.6502 12.8573C14.4945 12.7087 14.3559 12.6651 14.25 12.6651C14.1441 12.6651 14.0055 12.7087 13.8498 12.8573L13.7071 13L14.3536 13.6464C14.5488 13.8417 14.5488 14.1583 14.3536 14.3536C14.1583 14.5488 13.8417 14.5488 13.6464 14.3536L11.1502 11.8573C10.9945 11.7087 10.8559 11.6651 10.75 11.6651C10.6441 11.6651 10.5055 11.7087 10.3498 11.8573L8 14.2071V15C8 15.2652 8.10536 15.5196 8.29289 15.7071C8.48043 15.8946 8.73478 16 9 16H15C15.2652 16 15.5196 15.8946 15.7071 15.7071C15.8946 15.5196 16 15.2652 16 15V14.2071ZM13 10C13 9.72386 13.2239 9.5 13.5 9.5H13.505C13.7811 9.5 14.005 9.72386 14.005 10C14.005 10.2761 13.7811 10.5 13.505 10.5H13.5C13.2239 10.5 13 10.2761 13 10Z"
        data-part="fallback-image-label"
      />
    </svg>
    """
  end
end
