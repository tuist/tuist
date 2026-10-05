defmodule Tuist.MCP.Events do
  @moduledoc """
  Project-scoped subscriptions for agent-triggering events.
  """

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.MCP.Authorization
  alias Tuist.MCP.Events.Callback
  alias Tuist.MCP.Events.Subscription
  alias Tuist.MCP.Events.Workers.FanoutWorker
  alias Tuist.Projects
  alias Tuist.Repo

  require Logger

  @project_events ["test_case.marked_flaky", "build.failed", "test_run.failed"]
  @account_events ["ci_job.failed"]
  @supported_events @project_events ++ @account_events
  @default_ttl_ms 7 * 24 * 60 * 60 * 1_000
  @maximum_ttl_ms 30 * 24 * 60 * 60 * 1_000
  @maximum_subscriptions_per_user 25

  def list do
    %{
      "events" => [
        descriptor("test_case.marked_flaky", "A test case in the selected project was marked flaky.", project_schema(), [
          "test_case_id"
        ]),
        descriptor("build.failed", "A build in the selected project failed.", project_schema(), [
          "build_id",
          "build_system"
        ]),
        descriptor("test_run.failed", "A test run in the selected project failed.", project_schema(), ["test_run_id"]),
        descriptor(
          "ci_job.failed",
          "A continuous integration runner job in the selected account failed.",
          account_schema(),
          ["workflow_job_id", "workflow_run_id"]
        )
      ]
    }
  end

  def subscribe(conn, %{"name" => name, "arguments" => args, "delivery" => delivery} = params)
      when name in @supported_events and is_map(args) and is_map(delivery) do
    with {:ok, user, credential, target} <- authorized_target(conn, name, args),
         %{"mode" => "webhook", "url" => url, "secret" => secret} when is_binary(url) <- delivery,
         true <- Callback.valid_secret?(secret),
         id = subscription_id(user.id, credential, url, name, target),
         true <- subscription_available?(user.id, id),
         :ok <- Callback.verify(url, secret, id) do
      ttl_ms = requested_ttl(params["ttlMs"])
      refresh_before = DateTime.utc_now() |> DateTime.add(ttl_ms, :millisecond) |> DateTime.truncate(:second)

      attrs =
        credential
        |> Map.merge(target)
        |> Map.merge(%{
          id: id,
          user_id: user.id,
          event_name: name,
          callback_url: url,
          signing_secret: secret,
          refresh_before: refresh_before
        })

      case save_subscription(attrs) do
        {:ok, :ok} ->
          {:ok,
           %{"id" => id, "refreshBefore" => DateTime.to_iso8601(refresh_before), "cursor" => nil, "truncated" => false}}

        {:error, :limit} ->
          {:error, -32_602, "Subscription limit reached"}

        {:error, {:changeset, changeset}} ->
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

  def unsubscribe(conn, %{"name" => name, "arguments" => args, "delivery" => %{"url" => url}})
      when name in @supported_events and is_map(args) and is_binary(url) do
    case authorized_target(conn, name, args) do
      {:ok, user, credential, target} ->
        id = subscription_id(user.id, credential, url, name, target)
        Repo.delete_all(from s in Subscription, where: s.id == ^id and s.user_id == ^user.id)
        {:ok, %{}}

      _ ->
        {:ok, %{}}
    end
  end

  def unsubscribe(_conn, _params), do: {:error, -32_602, "Invalid event subscription"}

  def publish_marked_flaky(project_id, test_case_id, source_id) do
    publish("test_case.marked_flaky", %{"project_id" => project_id, "test_case_id" => test_case_id}, source_id)
  end

  def publish_failed_build(project_id, build_system, build_id) do
    publish(
      "build.failed",
      %{"project_id" => project_id, "build_system" => build_system, "build_id" => build_id},
      "#{build_system}:#{build_id}"
    )
  end

  def publish_failed_builds(project_id, build_system, build_ids) when is_list(build_ids) do
    if build_ids != [] and active_subscriptions?("build.failed", %{"project_id" => project_id}) do
      Enum.each(build_ids, fn build_id ->
        enqueue(
          "build.failed",
          %{"project_id" => project_id, "build_system" => build_system, "build_id" => build_id},
          "#{build_system}:#{build_id}"
        )
      end)
    end

    :ok
  end

  def publish_failed_test_run(project_id, test_run_id) do
    publish("test_run.failed", %{"project_id" => project_id, "test_run_id" => test_run_id}, test_run_id)
  end

  def publish_failed_ci_job(account_id, workflow_run_id, workflow_job_id) do
    publish(
      "ci_job.failed",
      %{"account_id" => account_id, "workflow_run_id" => workflow_run_id, "workflow_job_id" => workflow_job_id},
      workflow_job_id
    )
  end

  defp publish(name, data, source_id) do
    if active_subscriptions?(name, data) do
      enqueue(name, data, source_id)
    else
      :ok
    end
  end

  defp enqueue(name, data, source_id) do
    args = data |> Map.put("event_name", name) |> Map.put("source_id", to_string(source_id))

    case Oban.insert(FanoutWorker.new(args)) do
      {:ok, _job} -> :ok
      {:error, reason} -> Logger.warning("MCP event fan-out could not be queued: #{inspect(reason)}")
    end
  end

  defp active_subscriptions?(name, data) do
    now = DateTime.utc_now()
    query = from s in Subscription, where: s.event_name == ^name and s.refresh_before > ^now

    query =
      if project_id = data["project_id"] do
        where(query, [s], s.project_id == ^project_id)
      else
        account_id = data["account_id"]
        where(query, [s], s.account_id == ^account_id and is_nil(s.project_id))
      end

    Repo.exists?(query)
  end

  defp subscription_available?(user_id, id) do
    now = DateTime.utc_now()

    Repo.exists?(from s in Subscription, where: s.id == ^id) or
      Repo.aggregate(from(s in Subscription, where: s.user_id == ^user_id and s.refresh_before > ^now), :count, :id) <
        @maximum_subscriptions_per_user
  end

  defp save_subscription(attrs) do
    Repo.transaction(fn ->
      Ecto.Adapters.SQL.query!(Repo, "SELECT pg_advisory_xact_lock(7001, $1::integer)", [attrs.user_id])

      if subscription_available?(attrs.user_id, attrs.id) do
        case %Subscription{}
             |> Subscription.changeset(attrs)
             |> Repo.insert(
               on_conflict: {:replace, [:signing_secret, :refresh_before, :updated_at]},
               conflict_target: :id
             ) do
          {:ok, _subscription} -> :ok
          {:error, changeset} -> Repo.rollback({:changeset, changeset})
        end
      else
        Repo.rollback(:limit)
      end
    end)
  end

  defp authorized_target(conn, name, args) when name in @project_events do
    category = if name == "build.failed", do: :build, else: :test
    authorized_project(conn, args, category)
  end

  defp authorized_target(conn, name, args) when name in @account_events, do: authorized_account(conn, args)

  defp authorized_project(
         %{assigns: assigns} = conn,
         %{"account_handle" => account_handle, "project_handle" => project_handle} = args,
         category
       )
       when is_binary(account_handle) and is_binary(project_handle) and map_size(args) == 2 do
    with %AuthenticatedAccount{} = subject <- assigns[:current_subject],
         %User{} = user <- assigns[:current_user] || subject.issued_by,
         %Projects.Project{} = project <-
           Projects.get_project_by_account_and_project_handles(account_handle, project_handle),
         true <-
           Accounts.owns_account_or_is_member_of_account_organization?(user, Repo.preload(project.account, :organization)),
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
         %Accounts.Account{} = account <- Accounts.get_account_by_handle(account_handle),
         true <- Accounts.owns_account_or_is_member_of_account_organization?(user, Repo.preload(account, :organization)),
         true <- Authorization.authorize(user, :read, account, :runners),
         true <- Authorization.authorize(subject, :read, account, :runners),
         {:ok, credential} <- credential(conn, user, subject) do
      {:ok, user, credential, %{account_id: account.id, project_id: nil}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp authorized_account(_conn, _args), do: {:error, :invalid_arguments}

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

  defp subscription_id(user_id, credential, url, event_name, target) do
    credential_id = credential[:oauth_client_id] || credential[:account_token_id]
    target_id = target[:project_id] || "account:#{target[:account_id]}"
    digest = :crypto.hash(:sha256, "#{user_id}:#{credential_id}:#{url}:#{event_name}:#{target_id}")
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

  defp account_schema do
    %{
      "type" => "object",
      "properties" => %{"account_handle" => %{"type" => "string"}},
      "required" => ["account_handle"],
      "additionalProperties" => false
    }
  end

  defp descriptor(name, description, input_schema, fields) do
    properties =
      fields
      |> Enum.reduce(%{"account_handle" => %{"type" => "string"}, "url" => %{"type" => "string"}}, fn
        field, acc ->
          Map.put(acc, field, %{
            "type" => if(field in ["workflow_job_id", "workflow_run_id"], do: "integer", else: "string")
          })
      end)
      |> then(fn props ->
        if name == "ci_job.failed", do: props, else: Map.put(props, "project_handle", %{"type" => "string"})
      end)

    %{
      "name" => name,
      "description" => description,
      "delivery" => ["webhook"],
      "inputSchema" => input_schema,
      "payloadSchema" => %{
        "type" => "object",
        "properties" => properties,
        "required" => Map.keys(properties),
        "additionalProperties" => false
      }
    }
  end
end
