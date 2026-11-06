defmodule AtlasWeb.MoodboardMedia do
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :resource, :map, required: true
  attr :id, :string, required: true
  attr :detail, :boolean, default: false

  def media(assigns) do
    assigns =
      assigns
      |> assign(:image, assigns.resource.image_url || assigns.resource.preview_image_url)
      |> then(fn assigns ->
        video =
          if !assigns.resource.image_url and assigns.resource.kind == "video" and (assigns.image || assigns.detail),
            do: assigns.resource.preview_video_url

        assign(assigns, :video, video)
      end)

    ~H"""
    <div data-part="preview">
      <span data-part="preview-fallback" aria-hidden="true">
        {if @resource.url, do: URI.parse(@resource.url).host, else: @resource.title}
      </span>
      <video
        :if={@video}
        id={@id <> "-video"}
        src={@video}
        poster={@image}
        controls
        playsinline
        preload="none"
        aria-label={@resource.title}
        phx-hook="MoodboardVideo"
        phx-mounted={JS.ignore_attributes(["hidden"])}
      >
        <a href={@resource.url} target="_blank" rel="noopener noreferrer">{@resource.title}</a>
      </video>
      <img
        :if={@image && !@video}
        id={@id <> "-image"}
        src={@image}
        alt=""
        loading="lazy"
        decoding="async"
        referrerpolicy="no-referrer"
        phx-hook="MoodboardImage"
        phx-mounted={JS.ignore_attributes(["hidden"])}
      />
    </div>
    """
  end
end
