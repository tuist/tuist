defmodule TuistWeb.OnceActionComponents do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.Helpers.VCSLinks

  alias Tuist.OnceEvents.Presentation

  attr :label, :string, required: true
  attr :target, :string, required: true
  attr :presentation, :map, default: nil

  def action_cell(assigns) do
    assigns = assign(assigns, :description, summary(assigns.presentation, assigns.target))

    ~H"""
    <div data-part="cell" data-type="text_and_description" data-truncate data-once-action>
      <div data-part="column">
        <span data-part="label" title={@label}>{@label}</span>
        <span data-part="description" title={@description}>{@description}</span>
      </div>
    </div>
    """
  end

  def summary(presentation, target) do
    case Presentation.normalize(presentation) do
      nil ->
        target

      metadata ->
        metadata
        |> badges()
        |> Enum.take(2)
        |> Enum.map_join(" · ", fn {label, _title} -> label end)
    end
  end

  def badges(metadata) do
    package =
      case metadata["package"] do
        nil ->
          []

        package ->
          version =
            Enum.find([package["version"], short_id(package["revision"]), short_id(package["digest"])], &(&1 != "")) || ""

          [{String.trim(package["name"] <> " " <> version), package["ecosystem"]}]
      end

    platforms =
      Enum.map(metadata["platforms"], fn platform ->
        label = if platform["label"] == "", do: platform["id"], else: platform["label"]

        label =
          if platform["usage"] == "build-tool",
            do: dgettext("dashboard_projects", "Build tool") <> " · " <> label,
            else: label

        {label, platform["scheme"] <> ":" <> platform["id"]}
      end)

    context =
      Enum.map(metadata["context"], fn context ->
        label = if context["label"] == "", do: context["key"] <> ": " <> context["value"], else: context["label"]
        {label, context["key"] <> "=" <> context["value"]}
      end)

    package ++ platforms ++ context
  end

  def label(%{display_name: name}) when is_binary(name) and name != "", do: name
  def label(%{identifier: identifier}) when is_binary(identifier) and identifier != "", do: identifier
  def label(%{action_index: index}), do: dgettext("dashboard_projects", "Action %{index}", index: index + 1)

  def cache_status(%{was_cached: true}), do: dgettext("dashboard_projects", "Hit")
  def cache_status(%{cache_key: key}) when is_binary(key) and key != "", do: dgettext("dashboard_projects", "Miss")
  def cache_status(_), do: dgettext("dashboard_projects", "Not reported")

  def status("succeeded"), do: dgettext("dashboard_projects", "Succeeded")
  def status("failed"), do: dgettext("dashboard_projects", "Failed")
  def status("skipped"), do: dgettext("dashboard_projects", "Skipped")
  def status("cancelled"), do: dgettext("dashboard_projects", "Cancelled")
  def status("timed_out"), do: dgettext("dashboard_projects", "Timed out")
  def status("infrastructure_error"), do: dgettext("dashboard_projects", "Infrastructure error")
  def status(_), do: dgettext("dashboard_projects", "Unknown")

  def status_variant("succeeded"), do: "success"
  def status_variant(result) when result in ["failed", "timed_out", "infrastructure_error"], do: "error"
  def status_variant(result) when result in ["skipped", "cancelled"], do: "disabled"
  def status_variant(_), do: "attention"

  def source_rows(action) do
    files = action.source_files || []
    statuses = action.source_file_statuses || []

    if statuses != [] and length(statuses) == length(files) do
      files
      |> Enum.zip(statuses)
      |> Enum.with_index()
      |> Enum.map(fn {{file, status}, index} -> %{file: file, link?: status == 1, index: index} end)
    else
      files
      |> Enum.with_index()
      |> Enum.map(fn {file, index} -> %{file: file, link?: statuses == [], index: index} end)
    end
  end

  attr :row, :map, required: true
  attr :project, :map, required: true
  attr :run, :map, required: true

  def source_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="text" data-source-file>
      <.source_file_link
        :if={@row.link?}
        project={@project}
        path={@row.file}
        commit_sha={@run.git_rev}
      />
      <span :if={!@row.link?} data-part="sublabel">{@row.file}</span>
    </div>
    """
  end

  defp short_id(nil), do: ""
  defp short_id(value), do: String.slice(value, 0, 12)
end
