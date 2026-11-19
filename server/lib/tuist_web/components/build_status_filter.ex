defmodule TuistWeb.Components.BuildStatusFilter do
  @moduledoc """
  The Status filter the build dashboards share: Any, Passed or Failed builds,
  read from the `analytics-build-status` query parameter and passed to the
  analytics queries as the `:status` option.
  """
  use Phoenix.Component
  use Noora
  use Gettext, backend: TuistWeb.Gettext

  alias TuistWeb.Utilities.Query

  @param "analytics-build-status"
  @statuses ["any", "success", "failure"]

  def param, do: @param

  def status(params) do
    case params[@param] do
      status when status in ["success", "failure"] -> status
      _ -> "any"
    end
  end

  def put_status(opts, "any"), do: opts
  def put_status(opts, status), do: Keyword.put(opts, :status, status)

  @doc """
  The failed-builds series for the selected status. `fetch` queries the
  failures with the remaining filters; a Passed selection has none.
  """
  def failed_builds_analytics("success", total_builds_analytics, _fetch) do
    %{
      total_builds_analytics
      | trend: 0.0,
        count: 0,
        values: Enum.map(total_builds_analytics.values, fn _ -> 0 end)
    }
  end

  def failed_builds_analytics(_status, _total_builds_analytics, fetch), do: fetch.()

  def status_label("success"), do: dgettext("dashboard_builds", "Passed")
  def status_label("failure"), do: dgettext("dashboard_builds", "Failed")
  def status_label(_any), do: dgettext("dashboard_builds", "Any")

  attr(:id, :string, required: true)
  attr(:status, :string, required: true)
  attr(:uri, URI, required: true)

  def build_status_dropdown(assigns) do
    assigns = assign(assigns, param: @param, statuses: @statuses)

    ~H"""
    <.dropdown
      id={@id}
      label={status_label(@status)}
      secondary_text={dgettext("dashboard_builds", "Status:")}
    >
      <.dropdown_item
        :for={status <- @statuses}
        value={status}
        label={status_label(status)}
        patch={"?#{Query.put(@uri.query, @param, status)}"}
        data-selected={@status == status}
      >
        <:right_icon :if={@status == status}><.check /></:right_icon>
      </.dropdown_item>
    </.dropdown>
    """
  end
end
