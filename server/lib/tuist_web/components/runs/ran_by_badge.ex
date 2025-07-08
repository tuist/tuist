defmodule TuistWeb.Runs.RanByBadge do
  @moduledoc """
  A component used to render a badge indicating who executed the run.
  """
  use TuistWeb, :html
  use Noora

  attr :run, :map, required: true

  def run_ran_by_badge_cell(assigns) do
    ~H"""
    <.badge_cell
      :if={@run.is_ci}
      label={gettext("CI")}
      icon="settings"
      color="information"
      style="light-fill"
    />
    <.badge_cell
      :if={Map.has_key?(@run, :user) and not is_nil(@run.user)}
      label={@run.user.account.name}
      icon="user"
      color="primary"
      style="light-fill"
    />
    <.badge_cell
      :if={!@run.is_ci and (!Map.has_key?(@run, :user) or is_nil(@run.user))}
      label={gettext("Unknown")}
      color="neutral"
      style="light-fill"
    />
    """
  end

  attr :build, :map, required: true

  def build_ran_by_badge_cell(assigns) do
    ~H"""
    <.badge_cell
      :if={@build.is_ci}
      label={gettext("CI")}
      icon="settings"
      color="information"
      style="light-fill"
    />
    <.badge_cell
      :if={not @build.is_ci and not is_nil(@build.ran_by_account)}
      label={@build.ran_by_account.name}
      icon="user"
      color="primary"
      style="light-fill"
    />
    """
  end
end
