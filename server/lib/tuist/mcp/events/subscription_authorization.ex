defmodule Tuist.MCP.Events.SubscriptionAuthorization do
  @moduledoc false

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.MCP.Authorization
  alias Tuist.MCP.Events.Catalog
  alias Tuist.MCP.Events.OAuthGrants
  alias Tuist.MCP.Events.Subscription
  alias Tuist.OAuth.Clients
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Repo

  def authorized_target(conn, name, args) do
    case Catalog.target(name) do
      {:project, category} -> authorized_project(conn, args, category)
      {:account, :runners} -> authorized_account(conn, args)
      nil -> {:error, :unsupported_event}
    end
  end

  defp authorized_project(
         %{assigns: assigns} = conn,
         %{"account_handle" => account_handle, "project_handle" => project_handle} = args,
         category
       )
       when is_binary(account_handle) and is_binary(project_handle) and map_size(args) == 2 do
    with %AuthenticatedAccount{} = subject <- assigns[:current_subject],
         %User{} = user <- assigns[:current_user] || subject.issued_by,
         %Project{} = project <-
           Projects.get_project_by_account_and_project_handles(account_handle, project_handle),
         true <- member?(user, project.account),
         true <- Authorization.authorize(user, :read, project, category),
         true <- Authorization.authorize(subject, :read, project, category),
         {:ok, credential} <- credential(conn, user, subject) do
      {:ok, user, credential, %{account_id: project.account_id, project_id: project.id}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp authorized_project(_conn, _args, _category), do: {:error, :invalid_arguments}

  defp authorized_account(%{assigns: assigns} = conn, %{"account_handle" => account_handle} = args)
       when is_binary(account_handle) and map_size(args) == 1 do
    with %AuthenticatedAccount{} = subject <- assigns[:current_subject],
         %User{} = user <- assigns[:current_user] || subject.issued_by,
         %Account{} = account <- Accounts.get_account_by_handle(account_handle),
         true <- member?(user, account),
         true <- Authorization.authorize(user, :read, account, :runners),
         true <- Authorization.authorize(subject, :read, account, :runners),
         {:ok, credential} <- credential(conn, user, subject) do
      {:ok, user, credential, %{account_id: account.id, project_id: nil}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp authorized_account(_conn, _args), do: {:error, :invalid_arguments}

  defp member?(user, %Account{} = account) do
    Accounts.owns_account_or_is_member_of_account_organization?(user, Repo.preload(account, :organization))
  end

  defp member?(user, %Project{} = project) do
    member?(user, project |> Repo.preload(:account) |> Map.fetch!(:account))
  end

  defp credential(_conn, _user, %AuthenticatedAccount{token_id: token_id}) when not is_nil(token_id),
    do: {:ok, %{account_token_id: token_id}}

  defp credential(conn, %User{id: user_id}, %AuthenticatedAccount{issued_by: %User{id: user_id}}) do
    with ["Bearer " <> token] <- Plug.Conn.get_req_header(conn, "authorization"),
         {:ok, %{"client_id" => client_id, "user_id" => ^user_id}} <- Tuist.Guardian.decode_and_verify(token),
         {:ok, _} <- Ecto.UUID.cast(client_id),
         %Boruta.Ecto.Token{} = grant <- OAuthGrants.find_bearer(token, client_id, user_id),
         {:ok, root_id} <- OAuthGrants.root_id(grant) do
      {:ok, %{oauth_client_id: client_id, oauth_grant_id: root_id}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp credential(_conn, _user, _subject), do: {:error, :unauthorized}

  def authorized?(subscription) do
    now = DateTime.utc_now()
    user = Repo.get(User, subscription.user_id)
    {resource, category} = authorization_target(subscription)

    match?(%User{active: true}, user) and not is_nil(resource) and member?(user, resource) and
      DateTime.after?(subscription.refresh_before, now) and
      Authorization.authorize(user, :read, resource, category) and
      credential_active?(subscription, user, resource, category)
  end

  defp authorization_target(%Subscription{event_name: name, account_id: account_id, project_id: project_id}) do
    case Catalog.target(name) do
      {:account, :runners} when is_nil(project_id) ->
        {Repo.get(Account, account_id), :runners}

      {:project, category} when not is_nil(project_id) ->
        case Repo.get(Project, project_id) do
          %Project{account_id: ^account_id} = project -> {project, category}
          _ -> {nil, category}
        end

      _ ->
        {nil, :test}
    end
  end

  defp credential_active?(%Subscription{oauth_client_id: client_id, oauth_grant_id: grant_id}, user, resource, category)
       when not is_nil(client_id) and not is_nil(grant_id) do
    case Clients.get_client(client_id) do
      %{refresh_token_ttl: refresh_token_ttl} when is_integer(refresh_token_ttl) ->
        case OAuthGrants.active_scope(grant_id, client_id, user.id, refresh_token_ttl) do
          {:ok, scope} ->
            scopes = String.split(scope, " ", trim: true)

            subject = %AuthenticatedAccount{
              account: Repo.preload(user, :account).account,
              scopes: scopes,
              all_projects: true,
              issued_by: user
            }

            Authorization.authorize(subject, :read, resource, category)

          :error ->
            false
        end

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
end
