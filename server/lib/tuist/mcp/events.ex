defmodule Tuist.MCP.Events do
  @moduledoc """
  Project-scoped subscriptions for agent-triggering events.
  """

  import Ecto.Query

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.MCP.Authorization
  alias Tuist.MCP.Events.Callback
  alias Tuist.MCP.Events.Subscription
  alias Tuist.MCP.Events.Workers.FanoutWorker
  alias Tuist.Projects
  alias Tuist.Repo

  require Logger

  @event_name "test_case.marked_flaky"
  @default_ttl_ms 7 * 24 * 60 * 60 * 1_000
  @maximum_ttl_ms 30 * 24 * 60 * 60 * 1_000

  def list do
    %{
      "events" => [
        %{
          "name" => @event_name,
          "description" => "A test case in the selected project was marked flaky.",
          "delivery" => ["webhook"],
          "inputSchema" => project_schema(),
          "payloadSchema" => %{
            "type" => "object",
            "properties" => %{
              "account_handle" => %{"type" => "string"},
              "project_handle" => %{"type" => "string"},
              "test_case_id" => %{"type" => "string"},
              "url" => %{"type" => "string"}
            },
            "required" => ["account_handle", "project_handle", "test_case_id", "url"],
            "additionalProperties" => false
          }
        }
      ]
    }
  end

  def subscribe(conn, %{"name" => @event_name, "arguments" => args, "delivery" => delivery} = params)
      when is_map(args) and is_map(delivery) do
    with {:ok, user, credential, project} <- authorized_project(conn, args),
         %{"mode" => "webhook", "url" => url, "secret" => secret} when is_binary(url) <- delivery,
         true <- Callback.valid_secret?(secret),
         id = subscription_id(user.id, credential, url, @event_name, project.id),
         :ok <- Callback.verify(url, secret, id) do
      ttl_ms = requested_ttl(params["ttlMs"])
      refresh_before = DateTime.utc_now() |> DateTime.add(ttl_ms, :millisecond) |> DateTime.truncate(:second)

      attrs =
        Map.merge(
          %{
            id: id,
            user_id: user.id,
            project_id: project.id,
            event_name: @event_name,
            callback_url: url,
            signing_secret: secret,
            refresh_before: refresh_before
          },
          credential
        )

      case %Subscription{}
           |> Subscription.changeset(attrs)
           |> Repo.insert(
             on_conflict: {:replace, [:signing_secret, :refresh_before, :updated_at]},
             conflict_target: :id
           ) do
        {:ok, _subscription} ->
          {:ok,
           %{"id" => id, "refreshBefore" => DateTime.to_iso8601(refresh_before), "cursor" => nil, "truncated" => false}}

        {:error, changeset} ->
          Logger.error("MCP event subscription could not be saved: #{inspect(changeset.errors)}")
          {:error, -32_603, "Subscription could not be saved"}
      end
    else
      {:error, reason} when reason in [:invalid_url, :timeout, :unreachable, :challenge_failed] ->
        {:error, -32_015, "Callback verification failed", %{"reason" => Atom.to_string(reason)}}

      _ ->
        {:error, -32_602, "Invalid or unauthorized event subscription"}
    end
  end

  def subscribe(_conn, _params), do: {:error, -32_602, "Invalid event subscription"}

  def unsubscribe(conn, %{"name" => @event_name, "arguments" => args, "delivery" => %{"url" => url}})
      when is_map(args) and is_binary(url) do
    case authorized_project(conn, args) do
      {:ok, user, credential, project} ->
        id = subscription_id(user.id, credential, url, @event_name, project.id)
        Repo.delete_all(from s in Subscription, where: s.id == ^id and s.user_id == ^user.id)
        {:ok, %{}}

      _ ->
        {:ok, %{}}
    end
  end

  def unsubscribe(_conn, _params), do: {:error, -32_602, "Invalid event subscription"}

  def publish_marked_flaky(project_id, test_case_id, source_id) do
    args = %{"project_id" => project_id, "test_case_id" => test_case_id, "source_id" => source_id}

    case Oban.insert(FanoutWorker.new(args)) do
      {:ok, _job} -> :ok
      {:error, reason} -> Logger.warning("MCP event fan-out could not be queued: #{inspect(reason)}")
    end
  end

  defp authorized_project(
         %{assigns: assigns} = conn,
         %{"account_handle" => account_handle, "project_handle" => project_handle} = args
       )
       when is_binary(account_handle) and is_binary(project_handle) and map_size(args) == 2 do
    subject = assigns[:current_subject]
    user = assigns[:current_user] || (match?(%AuthenticatedAccount{}, subject) && subject.issued_by)
    project = Projects.get_project_by_account_and_project_handles(account_handle, project_handle)

    case {user, subject, project} do
      {%User{} = user, %AuthenticatedAccount{} = subject, %Projects.Project{} = project} ->
        if Authorization.authorize(user, :read, project, :test) and
             Authorization.authorize(subject, :read, project, :test) do
          case credential(conn, user, subject) do
            {:ok, credential} -> {:ok, user, credential, project}
            error -> error
          end
        else
          {:error, :unauthorized}
        end

      _ ->
        {:error, :unauthorized}
    end
  end

  defp authorized_project(_conn, _args), do: {:error, :invalid_arguments}

  defp credential(_conn, _user, %AuthenticatedAccount{token_id: token_id}) when not is_nil(token_id),
    do: {:ok, %{account_token_id: token_id}}

  defp credential(conn, %User{id: user_id}, %AuthenticatedAccount{issued_by: %User{id: user_id}}) do
    with ["Bearer " <> token] <- Plug.Conn.get_req_header(conn, "authorization"),
         {:ok, %{"client_id" => client_id, "user_id" => ^user_id}} <- Tuist.Guardian.decode_and_verify(token),
         {:ok, _} <- Ecto.UUID.cast(client_id) do
      {:ok, %{oauth_client_id: client_id}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp credential(_conn, _user, _subject), do: {:error, :unauthorized}

  defp subscription_id(user_id, credential, url, event_name, project_id) do
    credential_id = credential[:oauth_client_id] || credential[:account_token_id]
    digest = :crypto.hash(:sha256, "#{user_id}:#{credential_id}:#{url}:#{event_name}:#{project_id}")
    "sub_" <> Base.url_encode64(digest, padding: false)
  end

  defp requested_ttl(ttl) when is_integer(ttl) and ttl > 0, do: min(ttl, @maximum_ttl_ms)
  defp requested_ttl(_ttl), do: @default_ttl_ms

  defp project_schema do
    %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string"},
        "project_handle" => %{"type" => "string"}
      },
      "required" => ["account_handle", "project_handle"],
      "additionalProperties" => false
    }
  end
end
