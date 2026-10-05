defmodule Tuist.MCP.Events.Workers.DeliveryWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 7,
    unique: [keys: [:subscription_id, :event_id], states: :all, period: {31, :days}]

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.MCP.Authorization
  alias Tuist.MCP.Events.Callback
  alias Tuist.MCP.Events.Subscription
  alias Tuist.Projects.Project
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subscription_id" => id, "event_id" => event_id, "body" => body}}) do
    case Repo.get(Subscription, id) do
      nil ->
        :ok

      subscription ->
        if authorized?(subscription) do
          deliver(subscription, event_id, body)
        else
          Repo.delete(subscription)
          :ok
        end
    end
  end

  defp authorized?(subscription) do
    now = DateTime.utc_now()
    user = Repo.get(User, subscription.user_id)
    project = Repo.get(Project, subscription.project_id)

    match?(%User{active: true}, user) and match?(%Project{}, project) and
      DateTime.after?(subscription.refresh_before, now) and
      Authorization.authorize(user, :read, project, :test) and
      credential_active?(subscription, user, project)
  end

  defp credential_active?(%Subscription{oauth_client_id: client_id}, %User{id: user_id}, _project)
       when not is_nil(client_id) do
    from(token in Boruta.Ecto.Token,
      where:
        token.client_id == ^client_id and token.sub == ^to_string(user_id) and
          token.type == "access_token" and not is_nil(token.refresh_token) and
          is_nil(token.revoked_at) and is_nil(token.refresh_token_revoked_at),
      select: token.scope
    )
    |> Repo.all()
    |> Enum.any?(fn scope ->
      scope in [nil, ""] or
        "project:tests:read" in (scope |> String.split(" ", trim: true) |> AccountToken.expand_scopes())
    end)
  end

  defp credential_active?(%Subscription{account_token_id: token_id}, user, project) when not is_nil(token_id) do
    case Repo.get(AccountToken, token_id) do
      %AccountToken{} = token ->
        token = Repo.preload(token, [:account, :projects])

        subject = %AuthenticatedAccount{
          account: token.account,
          scopes: token.scopes,
          all_projects: token.all_projects,
          project_ids: Enum.map(token.projects, & &1.id),
          token_id: token.id,
          issued_by: user
        }

        not Accounts.account_token_expired?(token) and Authorization.authorize(subject, :read, project, :test)

      _ ->
        false
    end
  end

  defp credential_active?(_subscription, _user, _project), do: false

  defp deliver(subscription, event_id, body) do
    encoded = JSON.encode!(body)

    if byte_size(encoded) > 262_144 do
      {:discard, :payload_too_large}
    else
      case Callback.post(subscription.callback_url, subscription.signing_secret, subscription.id, event_id, encoded) do
        {:ok, %{status: status}} when status in 200..299 -> :ok
        {:ok, %{status: 410}} -> Repo.delete(subscription)
        {:ok, %{status: 413}} -> {:discard, :payload_rejected}
        {:ok, %{status: status}} -> {:error, {:callback_status, status}}
        {:error, :invalid_callback_url} -> {:discard, :invalid_callback_url}
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
