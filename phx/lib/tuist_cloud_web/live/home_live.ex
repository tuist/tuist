defmodule TuistCloudWeb.HomeLive do
  use TuistCloudWeb, :live_view
  alias TuistCloud.Projects
  alias TuistCloud.CommandEvents
  alias TuistCloud.Time
  alias TuistCloud.Authorization

  def mount(params, _session, socket) do
    user = current_user()
    account = current_account(user)
    project = current_project(params)

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
        :date_range,
        params["date_range"]
      )
      |> assign(
        :projects,
        Projects.get_all_project_accounts(user)
      )
      |> assign(
        :can_update_billing,
        Authorization.can(user, :update, account, :billing)
      )
    }
  end

  def handle_params(params, _uri, socket) do
    project = current_project(params)

    date_range = if is_nil(params["date_range"]) do
      "last_30_days"
    else
      params["date_range"]
    end

    start_date =
      case date_range do
        "last_12_months" -> Date.add(Time.utc_now(), -365)
        "last_90_days" -> Date.add(Time.utc_now(), -90)
        "last_30_days" -> Date.add(Time.utc_now(), -30)
        "last_7_days" -> Date.add(Time.utc_now(), -7)
      end

    {
      :noreply,
      socket
      |> assign(
        :build_duration_analytics,
        CommandEvents.get_command_duration_analytics(
          "build",
          project_id: project.id,
          start_date: start_date
        )
      )
      |> assign(
        :cache_hit_rate_analytics,
        CommandEvents.get_cache_hit_rate_analytics(
          project_id: project.id,
          start_date: start_date
        )
      )
      |> assign(
        :date_range,
        date_range
      )
    }
  end

  def current_project(params) do
    Projects.get_project_by_account_and_project_name(params["owner"], params["project"])
  end

  def current_user do
    TuistCloud.Accounts.get_tuist_user()
  end

  def current_account(user) do
    user |> TuistCloud.Accounts.get_account_from_user()
  end
end
