defmodule AtlasWeb.OverviewLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.Widget

  alias Atlas.TuistOverview

  def mount(_params, _session, socket) do
    stats = TuistOverview.stats()

    {:ok,
     socket
     |> assign(:page_title, gettext("Overview"))
     |> assign(:stats, stats)
     |> assign(:cache_window_days, TuistOverview.cache_operations_window_days())}
  end

  def render(assigns) do
    ~H"""
    <div id="overview">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Overview")}</h1>
          <p data-part="description">
            {gettext("A live snapshot of Tuist pulled straight from the server.")}
          </p>
        </div>
      </div>

      <.card title={gettext("Tuist")} icon="chart_dots" data-part="tuist-card">
        <.card_section data-part="tuist-section">
          <div data-part="widgets">
            <.stat_widget
              id="overview-widget-users"
              title={gettext("Users")}
              result={@stats.users}
              legend_color="primary"
              tooltip_description={gettext("Total number of Tuist user accounts.")}
            />
            <.stat_widget
              id="overview-widget-organizations"
              title={gettext("Organizations")}
              result={@stats.organizations}
              legend_color="secondary"
              tooltip_description={gettext("Total number of Tuist organizations.")}
            />
            <.stat_widget
              id="overview-widget-projects"
              title={gettext("Projects")}
              result={@stats.projects}
              legend_color="attention"
              tooltip_description={gettext("Total number of Tuist projects across every account.")}
            />
            <.stat_widget
              id="overview-widget-jobs"
              title={gettext("Jobs")}
              result={@stats.jobs}
              legend_color="success"
              tooltip_description={
                gettext("Total number of runner jobs Tuist has scheduled for customers.")
              }
            />
            <.stat_widget
              id="overview-widget-cache-operations"
              title={gettext("Cache operations")}
              result={@stats.cache_operations}
              legend_color="neutral"
              tooltip_description={
                gettext(
                  "Xcode, Bazel and Gradle cache events served in the last %{days} days.",
                  days: @cache_window_days
                )
              }
              description={gettext("Last %{days} days", days: @cache_window_days)}
            />
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :result, :any, required: true
  attr :legend_color, :string, required: true
  attr :tooltip_description, :string, default: nil
  attr :description, :string, default: nil

  defp stat_widget(assigns) do
    case assigns.result do
      {:ok, value} ->
        assigns = assign(assigns, :value, format_count(value))

        ~H"""
        <.widget
          id={@id}
          title={@title}
          value={@value}
          description={@description}
          legend_color={@legend_color}
          tooltip_description={@tooltip_description}
        />
        """

      {:error, :not_configured} ->
        ~H"""
        <.widget
          id={@id}
          title={@title}
          legend_color={@legend_color}
          tooltip_description={@tooltip_description}
          empty
          empty_label={gettext("Not connected")}
        />
        """

      {:error, _reason} ->
        ~H"""
        <.widget
          id={@id}
          title={@title}
          legend_color="destructive"
          tooltip_description={@tooltip_description}
          empty
          empty_label={gettext("Unavailable")}
        />
        """
    end
  end

  defp format_count(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?=.)/, "\\0,")
    |> String.reverse()
  end
end
