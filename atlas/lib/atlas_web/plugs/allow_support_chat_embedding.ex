defmodule AtlasWeb.Plugs.AllowSupportChatEmbedding do
  @moduledoc false

  import Plug.Conn

  alias AtlasWeb.SupportChatEmbed

  def init(opts), do: opts

  def call(conn, _opts) do
    update_resp_header(conn, "content-security-policy", SupportChatEmbed.frame_ancestors(), &replace_frame_ancestors/1)
  end

  defp replace_frame_ancestors(policy) do
    frame_ancestors = SupportChatEmbed.frame_ancestors()

    if String.contains?(policy, "frame-ancestors") do
      Regex.replace(~r/frame-ancestors\s+[^;]+/, policy, frame_ancestors)
    else
      policy <> "; " <> frame_ancestors
    end
  end
end
