defmodule TuistCloudWeb.HomeLive do
  use TuistCloudWeb, :live_view
  alias TuistCloud.Projects

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
      |> assign(:build_average_durations, build_average_durations)
      |> assign(
        :build_total_average_duration,
        "#{Float.round(build_total_average_duration, 1)} s"
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
        "#{round(TuistCloud.CommandEvents.get_cache_hit_rate(project.id) * 100)} %"
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
