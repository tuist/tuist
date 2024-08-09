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
    [:analytics, :page, :view],
    [:analytics, :preview, :upload],
    [:analytics, :preview, :download],
    [:analytics, :cache_artifact, :upload],
    [:analytics, :cache_artifact, :download]
  ]

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
        %{email: email} = subject
      ) do
    run_if_enabled do
      :telemetry.execute(
        [:analytics, :organization, :create],
        %{},
        %{
          name: name,
          email: email
        }
        |> Map.merge(subject_parameters(subject))
      )
    end
  end

  def user_authenticate(%{email: email} = subject) do
    run_if_enabled do
      :telemetry.execute(
        [:analytics, :user, :authenticate],
        %{},
        %{email: email} |> Map.merge(subject_parameters(subject))
      )
    end
  end

  def user_create(%{email: email} = subject) do
    run_if_enabled do
      :telemetry.execute(
        [:analytics, :user, :create],
        %{},
        %{email: email} |> Map.merge(subject_parameters(subject))
      )
    end
  end

  def page_view(path, subject) do
    run_if_enabled do
      :telemetry.execute(
        [:analytics, :page, :view],
        %{},
        %{path: path} |> Map.merge(subject_parameters(subject))
      )
    end
  end

  def preview_upload(subject) do
    run_if_enabled do
      :telemetry.execute(
        [:analytics, :preview, :upload],
        %{},
        %{} |> Map.merge(subject_parameters(subject))
      )
    end
  end

  def preview_download(subject) do
    run_if_enabled do
      :telemetry.execute(
        [:analytics, :preview, :download],
        %{},
        %{} |> Map.merge(subject_parameters(subject))
      )
    end
  end

  def cache_artifact_upload(%{size: size, category: category}, subject) do
    run_if_enabled do
      :telemetry.execute(
        [:analytics, :cache_artifact, :upload],
        %{size: size},
        %{category: category} |> Map.merge(subject_parameters(subject))
      )
    end
  end

  def cache_artifact_download(%{size: size, category: category}, subject) do
    run_if_enabled do
      :telemetry.execute(
        [:analytics, :cache_artifact, :download],
        %{size: size},
        %{category: category} |> Map.merge(subject_parameters(subject))
      )
    end
  end

  def subject_parameters(%Tuist.Projects.Project{id: id}) do
    %{project_id: id}
  end

  def subject_parameters(%Tuist.Accounts.User{id: id}) do
    %{user_id: id}
  end
end
