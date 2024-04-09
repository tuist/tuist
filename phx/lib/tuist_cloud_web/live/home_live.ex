defmodule TuistCloudWeb.HomeLive do
  use TuistCloudWeb, :live_view
  alias TuistCloud.Projects
  alias TuistCloud.CommandEvents
  alias TuistCloud.Time

  def mount(params, _session, socket) do
    user = current_user()
    account = current_account(user)

    project =
      Projects.get_project_by_account_and_project_name(params["owner"], params["project"])

    build_average_durations =
      TuistCloud.CommandEvents.get_command_average(
        "build",
        project.id
      )

    build_total_average_duration =
      TuistCloud.CommandEvents.get_total_command_period_average_duration(
        "build",
        project.id
      )

    previous_build_total_average_duration =
      TuistCloud.CommandEvents.get_total_command_period_average_duration(
        "build",
        project.id,
        start_date: Date.add(Time.utc_now(), -60),
        end_date: Date.add(Time.utc_now(), -30)
      )

    build_average_duration_delta = CommandEvents.get_trend(
      previous_value: previous_build_total_average_duration,
      current_value: build_total_average_duration
    )

    current_cache_hit_rate = TuistCloud.CommandEvents.get_cache_hit_rate(project.id)
    previous_cache_hit_rate = TuistCloud.CommandEvents.get_cache_hit_rate(
      project.id,
      start_date: Date.add(Time.utc_now(), -60),
      end_date: Date.add(Time.utc_now(), -30)
    )
    cache_hit_rate_delta = CommandEvents.get_trend(
      previous_value: previous_cache_hit_rate,
      current_value: current_cache_hit_rate
    )

    cache_hit_rates = Map.values(TuistCloud.CommandEvents.get_cache_hit_rates(project.id))
    slug = Projects.get_project_slug_from_id(project.id)

    {
      :ok,
      socket
      |> assign(:current_user, user)
      |> assign(:current_account, account)
      |> assign(:current_owner, params["owner"])
      |> assign(:current_project, params["project"])
      |> assign(:page_title, gettext("Dashboard") <> " - #{slug}")
      |> assign(
        :projects,
        Projects.get_all_project_accounts(user)
      )
      |> assign(:build_average_durations, build_average_durations)
      |> assign(
        :build_total_average_duration,
        "#{Float.round(build_total_average_duration, 1)} s"
      )
      |> assign(
        :build_average_duration_delta,
        build_average_duration_delta
      )
      |> assign(
        :dates,
        Jason.encode!(
          Enum.map(
            Map.values(build_average_durations),
            &Calendar.strftime(&1.date, "%b %d")
          )
        )
      )
      |> assign(
        :build_average_duration_values,
        Jason.encode!(
          Enum.map(
            Map.values(build_average_durations),
            &round(&1.value)
          )
        )
      )
      |> assign(
        :cache_hit_rates,
        Jason.encode!(
          Enum.map(
            cache_hit_rates,
            &round(&1.value * 100)
          )
        )
      )
      |> assign(
        :cache_hit_rate,
        "#{round(current_cache_hit_rate * 100)} %"
      )
      |> assign(
        :cache_hit_rate_delta,
        Float.round(cache_hit_rate_delta, 1)
      )
    }
  end

  def current_user do
    TuistCloud.Accounts.get_tuist_user()
  end

  def current_account(user) do
    user |> TuistCloud.Accounts.get_account_from_user()
  end
end
