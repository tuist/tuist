defmodule TuistWeb.Runs.RanByBadge do
  @moduledoc """
  Shared actor presentation for reports. A client-reported identifier is never
  rendered with the same verified-user treatment as a database identity.
  """
  use TuistWeb, :html
  use Noora

  attr :run, :map, required: true
  attr :ran_by_name, :string, default: nil

  def run_ran_by_badge_cell(assigns) do
    ~H"""
    <.actor_badge_cell record={@run} legacy_name={@ran_by_name} />
    """
  end

  attr :build, :map, required: true

  def build_ran_by_badge_cell(assigns) do
    ~H"""
    <.actor_badge_cell record={@build} />
    """
  end

  attr :build, :map, required: true

  def gradle_build_ran_by_badge_cell(assigns) do
    ~H"""
    <.actor_badge_cell record={@build} />
    """
  end

  attr :test, :map, required: true

  def test_ran_by_badge_cell(assigns) do
    ~H"""
    <.actor_badge_cell record={@test} />
    """
  end

  attr :record, :map, required: true
  attr :legacy_name, :string, default: nil

  def actor_badge_cell(assigns) do
    assigns = assign(assigns, :actor, Tuist.ReportActor.actor(assigns.record, assigns.legacy_name))

    ~H"""
    <.badge_cell
      :if={@record.is_ci}
      label={dgettext("dashboard", "CI")}
      icon="settings"
      color="information"
      style="light-fill"
    />
    <.badge_cell
      :if={not @record.is_ci}
      label={
        if @actor.source == :reported,
          do: @actor.name <> " (" <> dgettext("dashboard", "Unverified") <> ")",
          else: @actor.name
      }
      icon={if @actor.source in [:verified, :legacy] and @actor.name != "Unknown", do: "user"}
      color={
        if @actor.source == :verified or (@actor.source == :legacy and @actor.name != "Unknown"),
          do: "primary",
          else: "neutral"
      }
      style="light-fill"
      data-actor-source={@actor.source}
      title={
        if @actor.source == :reported,
          do: dgettext("dashboard", "Reported by the build client, not verified.")
      }
    />
    """
  end
end
