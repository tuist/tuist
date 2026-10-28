defmodule AtlasWeb.SupportChatEmbed do
  @moduledoc false

  @default_parent_origins ["https://tuist.dev"]

  def parent_origins(config \\ Application.get_env(:atlas, :support_chat, [])) do
    Keyword.get(config, :parent_origins, @default_parent_origins)
  end

  def parent_origin(origin, parent_origins \\ parent_origins()) do
    if origin in parent_origins, do: origin
  end

  def frame_ancestors(parent_origins \\ parent_origins()) do
    "frame-ancestors 'self' " <> Enum.join(parent_origins, " ")
  end
end
