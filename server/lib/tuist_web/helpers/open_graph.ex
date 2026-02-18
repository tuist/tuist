defmodule TuistWeb.Helpers.OpenGraph do
  @moduledoc """
  Helper functions for generating Open Graph meta tag assigns.
  """

  alias Tuist.Projects.OpenGraph, as: ProjectsOpenGraph

  @doc """
  Returns Open Graph assigns for dashboard pages.
  """
  def og_image_assigns(image_name) when is_binary(image_name) do
    normalized_image_name = normalize_image_name(image_name)

    [
      head_twitter_card: "summary_large_image",
      head_open_graph_key_values:
        [%{key: "Page", value: page_label(normalized_image_name)}] ++ semantic_key_values(normalized_image_name)
    ]
  end

  def og_image_assigns(_image_name) do
    [head_twitter_card: "summary_large_image"]
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

  defp page_label(image_name) do
    image_name
    |> normalize_image_name()
    |> String.trim()
    |> String.replace(~r/[-_]+/, " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
    |> case do
      "" -> "Overview"
      label -> label
    end
  end

  defp semantic_key_values(image_name) do
    case normalize_image_name(image_name) do
      "overview" -> section_focus("Project", "Overview")
      "tests" -> section_focus("Quality", "Test Analytics")
      "test-runs" -> section_focus("Quality", "Test Runs")
      "test-cases" -> section_focus("Quality", "Test Cases")
      "test-case" -> section_focus("Quality", "Test Case")
      "test-run" -> section_focus("Quality", "Test Run")
      "flaky-tests" -> section_focus("Quality", "Flaky Tests")
      "quarantined-tests" -> section_focus("Quality", "Quarantined Tests")
      "module-cache" -> section_focus("Cache", "Module Cache")
      "cache-runs" -> section_focus("Cache", "Cache Runs")
      "generate-runs" -> section_focus("Cache", "Generate Runs")
      "xcode-cache" -> section_focus("Cache", "Xcode")
      "gradle-cache" -> section_focus("Cache", "Gradle")
      "connect" -> section_focus("Setup", "Project Connection")
      "bundles" -> section_focus("Binary Size", "Bundles")
      "bundle" -> section_focus("Binary Size", "Bundle Analysis")
      "builds" -> section_focus("Builds", "Overview")
      "build-runs" -> section_focus("Builds", "Build Runs")
      "build-run" -> section_focus("Builds", "Build Run")
      "previews" -> section_focus("Previews", "App Previews")
      "qa" -> section_focus("QA", "Runs")
      "qa-run" -> section_focus("QA", "Run Details")
      "run" -> section_focus("Builds", "Command Run")
      "settings" -> section_focus("Settings", "Project")
      "automations" -> section_focus("Settings", "Automations")
      "notifications" -> section_focus("Settings", "Notifications")
      "qa-settings" -> section_focus("Settings", "QA")
      _ -> []
    end
  end

  defp section_focus(section, focus) do
    [
      %{key: "Section", value: section},
      %{key: "Focus", value: focus}
    ]
  end

  defp normalize_image_name(image_name) do
    image_name
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end
end
