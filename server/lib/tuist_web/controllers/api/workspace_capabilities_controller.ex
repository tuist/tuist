defmodule TuistWeb.API.WorkspaceCapabilitiesController do
  @moduledoc "User-delegated account capabilities. Never returns installation credentials."
  use TuistWeb, :controller

  alias Boruta.Oauth.Token
  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Push
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Commands
  alias Tuist.Sandboxes.RepositoryCheckout
  alias Tuist.Sandboxes.Workspaces
  alias Tuist.VCS.Publications
  alias Tuist.VCS.RepositoryBroker
  alias TuistWeb.Authentication

  @repository_ops ~w(repositories repository_authorize repository_head repository_checkout repository_review repository_reconcile repository_publish publication_reconcile)

  def call_capability(conn, %{"account_handle" => handle}) do
    conn = put_resp_header(conn, "cache-control", "no-store")
    params = conn.body_params
    operation = params["operation"]

    scope =
      cond do
        operation in ["repository_publish", "publication_reconcile"] or
            (operation == "repository_authorize" and params["level"] == "write") ->
          "account:repositories:write"

        operation in @repository_ops ->
          "account:repositories:read"

        true ->
          "account:sandboxes:write"
      end

    with ["Bearer " <> bearer] <- get_req_header(conn, "authorization"),
         %User{} = issuer <- Authentication.oauth_user(conn),
         true <- Push.luft_app_session?(bearer, issuer),
         %Token{} = grant <- Boruta.AccessTokensAdapter.get_by(value: bearer),
         :ok <- Token.ensure_valid(grant),
         true <- scope in String.split(grant.scope || ""),
         %User{active: true, disabled_at: nil} = user <- Accounts.get_user_by_id(issuer.id),
         account when not is_nil(account) <- Accounts.get_account_by_handle(handle),
         :ok <- Authorization.authorize(:account_update, user, account),
         true <- FeatureFlags.luft_enabled?(user),
         true <- is_nil(account.organization_id) or FeatureFlags.organization_luft_enabled?(account),
         true <- FeatureFlags.sandboxes_enabled?(account),
         true <- valid_payload?(params),
         {:ok, result} <- dispatch(account, user, operation, params) do
      json(conn, %{result: result})
    else
      {:error, reason} when is_atom(reason) ->
        conn |> put_status(:conflict) |> json(%{code: reason})

      _ ->
        conn |> put_status(:not_found) |> json(%{code: :not_found})
    end
  end

  defp valid_payload?(params) do
    is_map(params) and map_size(params) <= 16 and byte_size(JSON.encode!(params)) <= 1_500_000
  end

  defp dispatch(account, _user, "ensure", %{"workspace_id" => key} = p) when map_size(p) == 2,
    do: map_sandbox(Workspaces.ensure(account, key))

  defp dispatch(account, _user, "show", %{"sandbox_id" => id} = p) when map_size(p) == 2,
    do: map_sandbox(Workspaces.fetch(account, id))

  defp dispatch(account, _user, "repositories", p) when map_size(p) == 1 do
    with {:ok, repositories} <- RepositoryBroker.list(account),
         do: {:ok, Enum.map(repositories, &Map.take(&1, [:full_name, :default_branch, :size]))}
  end

  defp dispatch(account, _user, op, %{"sandbox_id" => id, "work_id" => work} = p)
       when op in ["acquire", "renew", "release"] and map_size(p) == 3 do
    with true <- is_binary(work) and byte_size(work) in 1..200 and Regex.match?(~r/\A[a-zA-Z0-9:_-]+\z/, work),
         {:ok, sandbox} <- Workspaces.fetch(account, id) do
      case op do
        # Shared acquisition refuses another holder. A late acquire cannot
        # overwrite a newer run's residency; release is SQL compare-and-swap.
        "release" ->
          case Sandboxes.end_residency(sandbox.id, work) do
            :ok -> {:ok, %{}}
            {:ok, _} -> {:ok, %{}}
            error -> error
          end

        _ ->
          map_sandbox(Sandboxes.prepare_shared_residency(sandbox, work))
      end
    else
      false -> {:error, :invalid_request}
      error -> error
    end
  end

  defp dispatch(account, _user, "exec", %{"sandbox_id" => id, "argv" => argv} = p) do
    with true <- Enum.all?(Map.keys(p), &(&1 in ~w(operation sandbox_id argv cwd env timeout_ms))),
         true <- is_list(argv) and length(argv) in 1..256 and Enum.all?(argv, &bounded_string?(&1, 131_072)),
         true <- bounded_string?(p["cwd"] || "/workspace", 4096),
         true <- environment?(p["env"] || %{}),
         timeout = p["timeout_ms"] || 60_000,
         true <- is_integer(timeout) and timeout in 1..600_000,
         {:ok, sandbox} <- Workspaces.fetch(account, id) do
      Sandboxes.exec(sandbox, argv, cwd: p["cwd"] || "/workspace", env: p["env"] || %{}, timeout_ms: timeout)
    else
      false -> {:error, :invalid_request}
      error -> error
    end
  end

  defp dispatch(account, _user, op, %{"sandbox_id" => id, "command_id" => command_id} = p)
       when op in [
              "command_start",
              "command_read",
              "command_wait",
              "command_watch",
              "command_cancel",
              "command_stdin",
              "command_forget"
            ] do
    with true <- command_payload?(op, p),
         {:ok, _} <- Ecto.UUID.cast(command_id),
         {:ok, sandbox} <- Workspaces.fetch(account, id) do
      command(account, sandbox, op, command_id, p)
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp dispatch(account, user, op, %{"repository" => name} = p) when op in @repository_ops do
    level = if op == "repository_publish" or p["level"] == "write", do: :write, else: :read

    with {:ok, repository} <- RepositoryBroker.authorize(account, user, name, level) do
      case op do
        "repository_publish" ->
          publication(account, user, repository, p)

        "publication_reconcile" ->
          with {:ok, id} <- Ecto.UUID.cast(p["request_id"]), do: Publications.reconcile(account, user, id)

        _ ->
          repository(account, repository, op, p)
      end
    end
  end

  # Only named capabilities are admitted; in particular there is no credential
  # read capability. Publication goes exclusively through the durable ledger.
  defp dispatch(_, _, _, _), do: {:error, :unsupported_operation}

  defp repository(_account, repository, "repository_authorize", p) when map_size(p) == 2, do: {:ok, repository}

  defp repository(_account, repository, "repository_authorize", %{"level" => level} = p)
       when map_size(p) == 3 and level in ["read", "write"], do: {:ok, repository}

  defp repository(account, repository, "repository_head", %{"branch" => branch} = p) when map_size(p) == 3 do
    if branch?(branch),
      do: RepositoryBroker.branch_head(account, repository.name, branch),
      else: {:error, :invalid_request}
  end

  defp repository(account, repository, "repository_checkout", %{"sandbox_id" => id, "base_sha" => sha} = p)
       when map_size(p) == 4 do
    with true <- sha?(sha),
         :ok <- RepositoryCheckout.fits(repository),
         {:ok, sandbox} <- Workspaces.fetch(account, id) do
      RepositoryCheckout.stage(account, sandbox, repository.name, sha)
    else
      false -> {:error, :invalid_request}
      error -> error
    end
  end

  defp repository(account, repository, "repository_review", %{"snapshot" => raw, "objects" => objects} = p)
       when map_size(p) == 4 do
    with {:ok, snapshot} <- snapshot(raw, repository.name), do: RepositoryBroker.review(account, snapshot, objects)
  end

  defp repository(account, repository, "repository_reconcile", %{"snapshot" => raw} = p) when map_size(p) == 3 do
    with {:ok, snapshot} <- snapshot(raw, repository.name),
         :ok <- RepositoryBroker.reconcile(account, snapshot),
         do: {:ok, %{head_sha: snapshot.head_sha}}
  end

  defp repository(_, _, _, _), do: {:error, :invalid_request}

  defp publication(
         account,
         user,
         repository,
         %{"request_id" => request_id, "snapshot" => raw, "objects" => objects, "diff" => diff, "mode" => mode} = p
       )
       when map_size(p) == 7 do
    with {:ok, id} <- Ecto.UUID.cast(request_id),
         {:ok, snapshot} <- snapshot(raw, repository.name),
         true <- mode in ["direct", "branch"] and bounded_string?(diff, 131_072) and diff != "" do
      Publications.publish(
        account,
        user,
        id,
        Map.put(snapshot, :mode, if(mode == "direct", do: :direct, else: :branch)),
        objects,
        diff
      )
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp publication(_, _, _, _), do: {:error, :invalid_request}

  defp snapshot(
         %{"operation_id" => id, "base_sha" => base, "head_sha" => head, "target_branch" => branch} = raw,
         repository
       )
       when map_size(raw) == 4 do
    with {:ok, _} <- Ecto.UUID.cast(id), true <- sha?(base) and sha?(head) and branch?(branch) do
      {:ok, %{thread_id: id, base_sha: base, head_sha: head, target_branch: branch, repository: repository}}
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp snapshot(_, _), do: {:error, :invalid_request}

  defp command(_account, sandbox, "command_start", id, p) do
    with true <-
           Enum.all?(Map.keys(p), &(&1 in ~w(operation sandbox_id command_id command env cwd stdin residency timeout_ms))),
         true <- bounded_string?(p["command"], 131_072),
         true <- p["command"] != "",
         true <- environment?(p["env"] || %{}),
         true <- bounded_string?(p["cwd"] || "/workspace", 4096),
         true <- is_boolean(p["stdin"]),
         true <- bounded_string?(p["residency"], 200),
         true <- p["residency"] != "",
         true <- is_integer(p["timeout_ms"]),
         true <- p["timeout_ms"] in 1..21_600_000 do
      params = Map.new(~w(command env cwd stdin residency timeout_ms)a, &{&1, p[Atom.to_string(&1)]})
      Commands.start(sandbox, Map.put(params, :id, id))
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp command(_, sandbox, "command_read", id, p) do
    opts = [
      stdout_offset: p["stdout_offset"] || 0,
      stderr_offset: p["stderr_offset"] || 0,
      max_bytes: p["max_bytes"] || 65_536,
      wait_seconds: p["wait_seconds"] || 0
    ]

    with true <- Enum.all?(opts, fn {_, value} -> is_integer(value) and value in 0..9_223_372_036_854_775_807 end),
         true <- opts[:max_bytes] <= 1_048_576,
         true <- opts[:wait_seconds] <= 25 do
      Commands.read(sandbox, id, opts)
    else
      _ -> {:error, :invalid_request}
    end
  end

  defp command(_, sandbox, "command_wait", id, p) do
    wait = p["wait_seconds"] || 25
    if is_integer(wait) and wait in 0..25, do: Commands.wait(sandbox, id, wait), else: {:error, :invalid_request}
  end

  defp command(_, sandbox, "command_watch", id, p) do
    wait = p["wait_seconds"] || 25

    if is_integer(wait) and wait in 0..25,
      do: Workspaces.watch_command(sandbox, id, wait),
      else: {:error, :invalid_request}
  end

  defp command(_, sandbox, "command_cancel", id, _), do: Commands.cancel(sandbox, id)

  defp command(_, sandbox, "command_stdin", id, p) do
    if bounded_string?(p["data"], 65_536) and is_integer(p["offset"]) and p["offset"] >= 0 and
         p["offset"] <= 9_223_372_036_854_775_807 and is_boolean(p["close"]),
       do: Commands.write_stdin(sandbox, id, p["data"], p["close"], p["offset"]),
       else: {:error, :invalid_request}
  end

  defp command(_, sandbox, "command_forget", id, _) do
    Workspaces.forget_command(sandbox, id)
  end

  defp command_payload?(operation, params) do
    extra =
      case operation do
        "command_start" -> ~w(command env cwd stdin residency timeout_ms)
        "command_read" -> ~w(stdout_offset stderr_offset max_bytes wait_seconds)
        op when op in ["command_wait", "command_watch"] -> ~w(wait_seconds)
        "command_stdin" -> ~w(data offset close)
        _ -> []
      end

    Enum.all?(Map.keys(params), &(&1 in (~w(operation sandbox_id command_id) ++ extra)))
  end

  defp map_sandbox({:ok, sandbox}), do: {:ok, Map.take(sandbox, [:id, :account_id, :state, :residency_work_id])}
  defp map_sandbox(error), do: error

  defp bounded_string?(value, max),
    do: is_binary(value) and byte_size(value) <= max and String.valid?(value) and not String.contains?(value, <<0>>)

  defp environment?(env) when is_map(env) and map_size(env) <= 128,
    do: Enum.all?(env, fn {key, value} -> bounded_string?(key, 256) and bounded_string?(value, 65_536) end)

  defp environment?(_), do: false

  defp sha?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{40}\z/, value)

  defp branch?(value),
    do:
      bounded_string?(value, 255) and value != "" and not String.starts_with?(value, "-") and
        not String.contains?(value, ["..", "@{", "\\", " ", "~", "^", ":", "?", "*", "["])
end
