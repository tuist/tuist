defmodule TuistWeb.Helpers.OpenGraph do
  @moduledoc """
  Helper functions for generating Open Graph meta tag assigns.
  """

  alias Tuist.Projects.OpenGraph, as: ProjectsOpenGraph

  @doc """
  Returns default Open Graph assigns for dashboard pages.
  """
  def og_image_assigns do
    [head_twitter_card: "summary_large_image"]
  end

  @doc """
  Returns Open Graph assigns for dashboard pages with explicit key-values.
  """
  def og_image_assigns(key_values) when is_list(key_values) do
    [
      head_twitter_card: "summary_large_image",
      head_open_graph_key_values: key_values
    ]
  end

  def og_image_assigns(_key_values), do: og_image_assigns()

  @doc """
  Builds semantic Open Graph key-values for a page.
  """
  def semantic_key_values(page, section, focus) do
    [
      %{key: "Page", value: semantic_value(page, "Overview")},
      %{key: "Section", value: semantic_value(section, "Project")},
      %{key: "Focus", value: semantic_value(focus, "Overview")}
    ]
  end

  def resolved_head_image(assigns) do
    if is_binary(assigns[:head_image]) do
      assigns[:head_image]
    else
      public_project_head_image(assigns)
    end
  end

  def resolved_twitter_card(assigns) do
    if is_binary(assigns[:head_twitter_card]) do
      assigns[:head_twitter_card]
    else
      default_twitter_card(assigns)
    end
  end

  defp public_project_head_image(assigns) do
    with %{visibility: :public, name: project_handle} = project <- assigns[:selected_project],
         %{name: account_handle} = account <- assigns[:selected_account] do
      title = ProjectsOpenGraph.default_title(assigns[:head_title])
      key_values = resolve_key_values(assigns, account, project)

      ProjectsOpenGraph.image_url(account_handle, project_handle, title, key_values)
    else
      _ ->
        Tuist.Environment.app_url(path: "/images/open-graph/card.jpeg")
    end
  end

  defp default_twitter_card(assigns) do
    if public_project?(assigns) do
      "summary_large_image"
    else
      "summary"
    end
  end

  defp public_project?(assigns) do
    case assigns[:selected_project] do
      %{visibility: :public} -> true
      _ -> false
    end
  end

  defp resolve_key_values(assigns, account, project) do
    custom_key_values =
      assigns
      |> Map.get(:head_open_graph_key_values, [])
      |> List.wrap()

    default_key_values = ProjectsOpenGraph.default_key_values(account, project)

    key_values =
      if custom_key_values == [] do
        page_title = ProjectsOpenGraph.default_title(assigns[:head_title])
        [%{key: "Page", value: page_title} | default_key_values]
      else
        custom_key_values ++ default_key_values
      end

    Enum.take(key_values, 3)
  end

  defp semantic_value(value, fallback) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> fallback
      value -> value
    end
  end
end
