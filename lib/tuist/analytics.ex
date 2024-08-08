defmodule Tuist.Analytics do
  @moduledoc ~S"""
  A module that provides an interface to send analytic events across the application.
  The module uses the `telemetry` to broadcast events, which are then handled by the respective analytics modules.
  """

  # Naming convention: https://posthog.com/product-engineers/5-ways-to-improve-analytics-data#1-implement-a-naming-convention

  @all_events [
    [:analytics, :organization, :create],
    [:analytics, :user, :create],
    [:analytics, :user, :authenticate],
    [:analytics, :page, :view]
  ]

  def enabled?() do
    !Tuist.Environment.on_premise?() and Tuist.Environment.env() == :prod
  end

  def all_events() do
    @all_events
  end

  defmacro run_if_enabled(do: block) do
    quote do
      if Tuist.Environment.analytics_enabled?() do
        unquote(block)
      else
        :ok
      end
    end
  end

  def organization_create(
        name,
        %{email: email, id: user_id}
      ) do
    run_if_enabled do
      :telemetry.execute([:analytics, :organization, :create], %{
        name: name,
        email: email,
        user_id: user_id
      })
    end
  end

  def user_authenticate(%{email: email, id: user_id}) do
    run_if_enabled do
      :telemetry.execute(
        [:analytics, :user, :authenticate],
        %{email: email, user_id: user_id}
      )
    end
  end

  def user_create(%{email: email, id: user_id}) do
    run_if_enabled do
      :telemetry.execute(
        [:analytics, :user, :create],
        %{email: email, user_id: user_id}
      )
    end
  end

  def page_view(path, %{id: user_id}) do
    if enabled?() do
      :telemetry.execute(
        [:page, :view],
        %{path: path, user_id: user_id}
      )
    else
      :ok
    end
  end
end
