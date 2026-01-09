defmodule TuistWeb.Helpers.OpenGraph do
  @moduledoc """
  Helper functions for generating OpenGraph meta tag assigns for LiveView pages.
  """

  @doc """
  Returns OpenGraph assigns for public project dashboard pages.

  For public projects, returns assigns for `head_image` and `head_twitter_card`.
  For private projects, returns an empty list.

  ## Parameters

    * `project` - The project struct with a `visibility` field
    * `image_name` - The name of the image file (without extension or path prefix)

  ## Examples

      og_image_assigns(project, "overview")
      og_image_assigns(project, "build-runs")

  """
  @spec og_image_assigns(%{visibility: atom()}, String.t()) :: keyword()
  def og_image_assigns(%{visibility: :public}, image_name) do
    [
      head_image: Tuist.Environment.app_url(path: "/images/open-graph/dashboard/#{image_name}.webp"),
      head_twitter_card: "summary_large_image"
    ]
  end

  def og_image_assigns(_project, _image_name), do: []
end
