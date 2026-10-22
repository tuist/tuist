defmodule TuistWeb.Components.BuildMetadata do
  @moduledoc false
  use TuistWeb, :html

  import Noora.Table, only: [table: 1, text_cell: 1]

  alias Tuist.Builds.Metadata
  alias Tuist.Utilities.ByteFormatter

  attr :values, :map, default: %{}

  def build_metadata(assigns) do
    {observations, custom} = Metadata.partition(assigns.values)
    assigns = assign(assigns, observations: observations, custom: custom)

    ~H"""
    <div :if={@observations != []} data-part="custom-metadata-section" data-field="build-environment">
      <span data-part="custom-metadata-label">
        {dgettext("dashboard_builds", "Infrastructure and runner")}
      </span>
      <.table id="build-environment-table" rows={@observations} row_key={fn {key, _} -> key end}>
        <:col :let={{key, _value}} label={dgettext("dashboard_builds", "Reported property")}>
          <.text_cell label={label(key)} />
        </:col>
        <:col :let={{key, value}} label={dgettext("dashboard_builds", "Value")}>
          <.text_cell label={format_value(key, value)} />
        </:col>
      </.table>
    </div>
    <div :if={@custom != []} data-part="custom-metadata-section">
      <span data-part="custom-metadata-label">{dgettext("dashboard_builds", "Custom metadata")}</span>
      <.table id="custom-metadata-table" rows={@custom} row_key={fn {key, _} -> key end}>
        <:col :let={{key, _value}} label={dgettext("dashboard_builds", "Key")}>
          <.text_cell label={key} />
        </:col>
        <:col :let={{_key, value}} label={dgettext("dashboard_builds", "Value")}>
          <a
            :if={link?(value)}
            href={value}
            target="_blank"
            rel="noopener noreferrer"
            data-part="custom-metadata-link"
          >
            {value}
          </a>
          <.text_cell :if={not link?(value)} label={value} />
        </:col>
      </.table>
    </div>
    """
  end

  defp format_value(key, value) do
    case Metadata.kind(key, value) do
      :bytes -> ByteFormatter.format_bytes(String.to_integer(value))
      _ -> value
    end
  end

  defp link?(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) -> true
      _ -> false
    end
  end

  defp label("tuist.os.type"), do: dgettext("dashboard_builds", "Operating system")
  defp label("tuist.os.version"), do: dgettext("dashboard_builds", "Operating system version")
  defp label("tuist.os.kernel_version"), do: dgettext("dashboard_builds", "Kernel version")
  defp label("tuist.host.arch"), do: dgettext("dashboard_builds", "Process architecture")
  defp label("tuist.host.model"), do: dgettext("dashboard_builds", "Machine model")
  defp label("tuist.cpu.available_processors"), do: dgettext("dashboard_builds", "Available logical processors")
  defp label("tuist.memory.total_bytes"), do: dgettext("dashboard_builds", "Reported OS memory")
  defp label("tuist.process.locale"), do: dgettext("dashboard_builds", "Process locale")
  defp label("tuist.process.charset"), do: dgettext("dashboard_builds", "Default charset")
  defp label("tuist.jvm.vendor"), do: dgettext("dashboard_builds", "Java vendor")
  defp label("tuist.jvm.runtime_name"), do: dgettext("dashboard_builds", "Java runtime")
  defp label("tuist.jvm.runtime_version"), do: dgettext("dashboard_builds", "Java runtime version")
  defp label("tuist.jvm.vm_name"), do: dgettext("dashboard_builds", "Java VM")
  defp label("tuist.jvm.vm_version"), do: dgettext("dashboard_builds", "Java VM version")
  defp label("tuist.jvm.max_heap_bytes"), do: dgettext("dashboard_builds", "Maximum JVM heap")
  defp label("tuist.gradle.max_workers"), do: dgettext("dashboard_builds", "Maximum Gradle workers")
  defp label("tuist.ci.provider"), do: dgettext("dashboard_builds", "CI provider")
  defp label("tuist.ci.job"), do: dgettext("dashboard_builds", "CI job")
  defp label("tuist.ci.runner_environment"), do: dgettext("dashboard_builds", "Runner environment")
  defp label("tuist.ci.runner_name"), do: dgettext("dashboard_builds", "Runner name")
end
