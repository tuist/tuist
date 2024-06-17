defmodule TuistCloudWeb.HomeLive do
  use TuistCloudWeb, :live_view
  alias TuistCloud.Projects
  alias TuistCloud.CommandEvents
  alias TuistCloud.Time
  alias TuistCloud.Accounts

  def mount(params, session, %{assigns: %{selected_project: project}} = socket) do
    user_token = session["user_token"]

    if not is_nil(user_token) do
      user = Accounts.get_user_by_session_token(session["user_token"])
      Accounts.update_last_visited_project(user, project.id)
    end

    slug = Projects.get_project_slug_from_id(project.id)

    {
      :ok,
      socket
      |> assign(:page_title, gettext("Dashboard") <> " - #{slug}")
      |> assign(
        :date_range,
        params["date_range"]
      )
    }
  end

  def handle_event(
        "apply_filters",
        params,
        %{assigns: %{selected_project: project, selected_owner: owner, date_range: date_range}} =
          socket
      ) do
    ran_by =
      if is_nil(params["ran_by"]) do
        []
      else
        [] ++
          if params["ran_by"]["ci"] == "true" do
            ["ci"]
          else
            []
          end ++
          if params["ran_by"]["user"] == "true" do
            ["user"]
          else
            []
          end
      end

    query = %{
      ran_by: ran_by
    }

    query =
      if is_nil(date_range) do
        query
      else
        Map.put(query, "date_range", date_range)
      end

    {
      :noreply,
      socket
      |> redirect(to: ~p"/#{owner}/#{project.name}?#{query}")
    }
  end

  def handle_params(params, _uri, %{assigns: %{selected_project: project}} = socket) do
    date_range =
      if is_nil(params["date_range"]) do
        "last_30_days"
      else
        params["date_range"]
      end

    ran_by = params["ran_by"]

    start_date =
      case date_range do
        "last_12_months" -> Date.add(Time.utc_now(), -365)
        "last_30_days" -> Date.add(Time.utc_now(), -30)
        "last_7_days" -> Date.add(Time.utc_now(), -7)
      end

    opts = [
      project_id: project.id,
      start_date: start_date,
      is_ci: get_is_ci(ran_by)
    ]

    {
      :noreply,
      socket
      |> assign(
        :build_duration_analytics,
        CommandEvents.get_command_duration_analytics(
          "build",
          opts
        )
      )
      |> assign(
        :build_runs_analytics,
        CommandEvents.get_command_runs_analytics(
          "build",
          opts
        )
      )
      |> assign(
        :cache_duration_analytics,
        CommandEvents.get_command_duration_analytics(
          "cache",
          opts
        )
      )
      |> assign(
        :cache_runs_analytics,
        CommandEvents.get_command_runs_analytics(
          "cache",
          opts
        )
      )
      |> assign(
        :test_duration_analytics,
        CommandEvents.get_command_duration_analytics(
          "test",
          opts
        )
      )
      |> assign(
        :test_runs_analytics,
        CommandEvents.get_command_runs_analytics(
          "test",
          opts
        )
      )
      |> assign(
        :generate_duration_analytics,
        CommandEvents.get_command_duration_analytics(
          "generate",
          opts
        )
      )
      |> assign(
        :generate_runs_analytics,
        CommandEvents.get_command_runs_analytics(
          "generate",
          opts
        )
      )
      |> assign(
        :cache_hit_rate_analytics,
        CommandEvents.get_cache_hit_rate_analytics(opts)
      )
      |> assign(
        :date_range,
        date_range
      )
      |> assign(
        :ran_by,
        ran_by
      )
    }
  end

  attr :id, :string, required: true
  attr :trend, :float, required: true
  attr :trend_positive, :boolean, required: true
  attr :summary_value, :string, required: true
  attr :title, :string, required: true
  attr :type, :atom, default: :area

  def analytics_chart(assigns) do
    ~H"""
    <div class="analytics-section">
      <div class="analytics-section__header">
        <p class="text-sm font--medium"><%= @title %></p>
        <div class="analytics-section__header__highlight">
          <h4 class="text--semibold color--text-primary"><%= @summary_value %></h4>
          <%= if @trend != 0 do %>
            <div class={"analytics-section__header__change analytics-section__header__change--#{if @trend_positive do "positive" else "negative" end}"}>
              <%= if @trend < 0 do %>
                <.trend_down />
              <% else %>
                <.trend_up />
              <% end %>
              <span class="text--medium font--medium"><%= abs(Float.round(@trend, 1)) %> %</span>
            </div>
          <% end %>
        </div>
      </div>
      <chart-l id={@id} type={@type}></chart-l>
    </div>
    """
  end

  defp get_is_ci(ran_by) do
    cond do
      is_nil(ran_by) -> nil
      "ci" in ran_by and "user" in ran_by -> nil
      "ci" in ran_by -> true
      "user" in ran_by -> false
      true -> nil
    end
  end
end
