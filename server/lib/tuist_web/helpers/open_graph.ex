defmodule TuistWeb.Helpers.OpenGraph do
  @moduledoc """
  Helper functions for generating Open Graph meta tag assigns for LiveView pages.
  """

  alias Tuist.OpenGraphImageTemplates

  @image_token_salt "open_graph_image"

  @doc """
  Returns OpenGraph assigns for dashboard pages.

  Returns assigns for `head_image` and `head_twitter_card`. The images are
  generic and don't contain any project-specific information, so they are
  shown for all projects regardless of visibility.

  ## Parameters

    * `image_name` - The name of the image file (without extension or path prefix)

  ## Examples

      og_image_assigns("overview")
      og_image_assigns("build-runs")

  """
  def og_image_assigns(image_name) do
    [
      head_image: Tuist.Environment.app_url(path: "/images/open-graph/dashboard/#{image_name}.jpg"),
      head_twitter_card: "summary_large_image"
    ]
  end

  @doc """
  Builds a deterministic, signed, content-addressed Open Graph image path.

  ## Examples

      image_path(:marketing, title: "About Tuist", icon: "about")
      image_path(:docs, title: "Install Tuist", category: "Guides")

  """
  def image_path(template, variables) do
    params =
      Enum.reduce(variables, %{"template" => to_string(template)}, fn
        {_key, nil}, params ->
          params

        {key, value}, params ->
          Map.put(params, to_string(key), to_string(value))
      end)

    case OpenGraphImageTemplates.spec(params) do
      {:ok, spec} ->
        signed_params = Enum.sort(spec.params)

        signature =
          Phoenix.Token.sign(
            TuistWeb.Endpoint,
            @image_token_salt,
            signed_params,
            signed_at: 0
          )

        query = URI.encode_query(signed_params ++ [{"signature", signature}])
        "/open-graph-images/#{spec.key}.jpg?#{query}"

      :error ->
        raise ArgumentError, "invalid Open Graph image template variables"
    end
  end

  def verify_image_params(params, signature) when is_binary(signature) do
    signed_params = Enum.sort(params)

    case Phoenix.Token.verify(
           TuistWeb.Endpoint,
           @image_token_salt,
           signature,
           max_age: :infinity
         ) do
      {:ok, ^signed_params} -> :ok
      _ -> :error
    end
  end

  def verify_image_params(_params, _signature), do: :error
end
