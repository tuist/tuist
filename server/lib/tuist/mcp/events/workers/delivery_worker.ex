defmodule Tuist.MCP.Events.Workers.DeliveryWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 7,
    unique: [keys: [:subscription_id, :event_id], states: :all, period: {31, :days}]

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.MCP.Authorization
  alias Tuist.MCP.Events.Callback
  alias Tuist.MCP.Events.Subscription
  alias Tuist.OAuth.Clients
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
          {:ok, _subscription} = Repo.delete(subscription)
          :ok
        end
    end
  end

  defp authorized?(subscription) do
    now = DateTime.utc_now()
    user = Repo.get(User, subscription.user_id)
    {resource, category} = authorization_target(subscription)

    match?(%User{active: true}, user) and not is_nil(resource) and member?(user, resource) and
      DateTime.after?(subscription.refresh_before, now) and
      Authorization.authorize(user, :read, resource, category) and
      credential_active?(subscription, user, resource, category)
  end

  defp authorization_target(%Subscription{event_name: "ci_job.failed", account_id: account_id, project_id: nil}) do
    {Repo.get(Account, account_id), :runners}
  end

  defp authorization_target(%Subscription{event_name: name, account_id: account_id, project_id: project_id})
       when name in ["test_case.marked_flaky", "build.failed", "test_run.failed"] and not is_nil(project_id) do
    category = if name == "build.failed", do: :build, else: :test

    case Repo.get(Project, project_id) do
      %Project{account_id: ^account_id} = project -> {project, category}
      _ -> {nil, category}
    end
  end

  defp authorization_target(_subscription), do: {nil, :test}

  defp member?(user, %Project{} = project) do
    project = Repo.preload(project, account: :organization)
    Accounts.owns_account_or_is_member_of_account_organization?(user, project.account)
  end

  defp member?(user, %Account{} = account) do
    Accounts.owns_account_or_is_member_of_account_organization?(user, Repo.preload(account, :organization))
  end

  defp credential_active?(%Subscription{oauth_client_id: client_id}, %User{id: user_id}, _resource, category)
       when not is_nil(client_id) do
    case Clients.get_client(client_id) do
      %{refresh_token_ttl: refresh_token_ttl} when is_integer(refresh_token_ttl) ->
        client_id
        |> oauth_grants(user_id)
        |> Enum.any?(&oauth_grant_active?(&1, refresh_token_ttl, required_scope(category)))

      _ ->
        false
    end
  end

  defp credential_active?(%Subscription{account_token_id: token_id}, user, resource, category)
       when not is_nil(token_id) do
    case Repo.get(AccountToken, token_id) do
      %AccountToken{} = token ->
        token = Repo.preload(token, [:account, :projects])
        user_id = user.id

        subject = %AuthenticatedAccount{
          account: token.account,
          scopes: token.scopes,
          all_projects: token.all_projects,
          project_ids: Enum.map(token.projects, & &1.id),
          token_id: token.id
        }

        "mcp" in token.scopes and
          match?(%User{id: ^user_id}, Accounts.claimed_agent_registration_user(token.id)) and
          not Accounts.account_token_expired?(token) and
          Authorization.authorize(subject, :read, resource, category)

      _ ->
        false
    end
  end

  defp credential_active?(_subscription, _user, _resource, _category), do: false

  defp oauth_grants(client_id, user_id) do
    Repo.all(
      from token in Boruta.Ecto.Token,
        where:
          token.client_id == ^client_id and token.sub == ^to_string(user_id) and
            token.type == "access_token" and not is_nil(token.refresh_token) and
            is_nil(token.revoked_at) and is_nil(token.refresh_token_revoked_at),
        select: {token.scope, token.inserted_at}
    )
  end

  defp required_scope(:build), do: "project:builds:read"
  defp required_scope(:test), do: "project:tests:read"
  defp required_scope(:runners), do: "account:runners:read"

  defp oauth_grant_active?({scope, issued_at}, refresh_token_ttl, required_scope)
       when is_binary(scope) and is_integer(refresh_token_ttl) and not is_nil(issued_at) do
    DateTime.after?(DateTime.add(issued_at, refresh_token_ttl, :second), DateTime.utc_now()) and
      required_scope in (scope |> String.split(" ", trim: true) |> AccountToken.expand_scopes())
  end

  defp oauth_grant_active?(_grant, _refresh_token_ttl, _required_scope), do: false

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
