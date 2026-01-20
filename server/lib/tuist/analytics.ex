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
    [:analytics, :authentication, :token_refresh, :error]
  ]

  def all_events do
    @all_events
  end

  def organization_create(name, %{email: email} = subject) do
    :telemetry.execute(
      [:analytics, :organization, :create],
      %{},
      Map.merge(%{name: name, email: email}, subject_parameters(subject))
    )
  end

  def user_authenticate(%{email: email} = subject) do
    :telemetry.execute(
      [:analytics, :user, :authenticate],
      %{},
      Map.merge(%{email: email}, subject_parameters(subject))
    )
  end

  def user_create(%{email: email} = subject) do
    :telemetry.execute(
      [:analytics, :user, :create],
      %{},
      Map.merge(%{email: email}, subject_parameters(subject))
    )
  end

  def page_view(path, subject) do
    :telemetry.execute(
      [:analytics, :page, :view],
      %{},
      Map.merge(%{path: path}, subject_parameters(subject))
    )
  end

  def preview_upload(subject) do
    :telemetry.execute(
      [:analytics, :preview, :upload],
      %{},
      Map.merge(%{}, subject_parameters(subject))
    )
  end

  def preview_download(subject) do
    :telemetry.execute(
      [:analytics, :preview, :download],
      %{},
      Map.merge(%{}, subject_parameters(subject))
    )
  end

  def authentication_token_refresh_error(attrs) do
    :telemetry.execute(
      [:analytics, :authentication, :token_refresh, :error],
      %{},
      attrs
    )
  end

  def subject_parameters(%Tuist.Projects.Project{id: id}) do
    %{project_id: id}
  end

  def subject_parameters(%Tuist.Accounts.User{id: id}) do
    %{user_id: id}
  end

  def subject_parameters(%Tuist.Accounts.AuthenticatedAccount{account: %{id: id}}) do
    %{account_id: id}
  end
end
