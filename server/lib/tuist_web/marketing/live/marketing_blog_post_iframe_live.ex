defmodule TuistWeb.Marketing.MarketingBlogPostIframeLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Phoenix.Component

  def mount(%{"id" => id}, _session, socket) do
    socket =
      attach_hook(socket, :assign_template, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)

        template =
          uri.path
          |> String.trim_leading("/")
          |> String.replace(~r/[-\/]/, "_")
          |> String.replace("_iframe.html", "_#{String.trim(id, "\"")}")

        {:cont, assign(socket, template: template)}
      end)

    {:ok, socket}
  end
end
