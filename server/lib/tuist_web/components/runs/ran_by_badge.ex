defmodule TuistWeb.Runs.RanByBadge do
  @moduledoc """
  A component used to render a badge indicating who executed the run.
  """
  use TuistWeb, :html
  use Noora

  attr :run, :map, required: true
  attr :ran_by_name, :string, default: nil

  def run_ran_by_badge_cell(assigns) do
    ~H"""
    <.badge_cell
      :if={@run.is_ci}
      label={dgettext("dashboard", "CI")}
      icon="settings"
      color="information"
      style="light-fill"
    />
    <.badge_cell
      :if={not @run.is_ci and @ran_by_name}
      label={@ran_by_name}
      icon="user"
      color="primary"
      style="light-fill"
    />
    <.badge_cell
      :if={!@run.is_ci and !@ran_by_name}
      label={dgettext("dashboard", "Unknown")}
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
      label={dgettext("dashboard", "CI")}
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

  attr :test, :map, required: true

  def test_ran_by_badge_cell(assigns) do
    ~H"""
    <.badge_cell
      :if={@test.is_ci}
      label={dgettext("dashboard", "CI")}
      icon="settings"
      color="information"
      style="light-fill"
    />
    <.badge_cell
      :if={not @test.is_ci and not is_nil(@test.ran_by_account)}
      label={@test.ran_by_account.name}
      icon="user"
      color="primary"
      style="light-fill"
    />
    <.badge_cell
      :if={!@test.is_ci and is_nil(@test.ran_by_account)}
      label={dgettext("dashboard", "Unknown")}
      color="neutral"
      style="light-fill"
    />
    """
  end
end
