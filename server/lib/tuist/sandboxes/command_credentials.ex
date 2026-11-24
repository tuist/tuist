defmodule Tuist.Sandboxes.CommandCredentials do
  @moduledoc """
  The Tuist environment of a command someone starts in a member sandbox
  (`Sandboxes.member_sandbox?/1`) through the API: `Sandboxes.tuist_env/2`
  and, as `TUIST_OIDC_TOKEN`, a sandbox identity token that Tuist clients in
  the guest exchange (`TuistWeb.API.OIDCController`) for a short-lived
  account token, as CI does. CLIs from 4.215.0 exchange it with
  `tuist auth login`, and from 4.218.0 on their own, renewing it as it
  expires.

  The identity token is minted for each command, so a paused or long-lived
  sandbox never holds a stale one, and only exchanges while its command runs,
  at most until the command's deadline. It is signed with the token-signing
  secret under a salt of its own, is not a JWT any API accepts, and never
  enters `sandbox_commands`, logs or responses.

  Its grant never exceeds the cache access of whoever started the command:
  the CI preset when they may write the account's cache (for an account
  token, only the preset scopes it holds itself, and only its projects), read
  access when they may only read it, and no token otherwise. It never carries
  `account:sandboxes:write`.

  A macOS repository snapshot's build (`Tuist.Sandboxes.ClaudeCodeSnapshots`)
  starts its command as `:snapshot_build` in its builder, which is no member
  sandbox: while the build runs, the command gets read access to the
  account's cache, so the script's `tuist generate` writes the same project
  as a signed-in session's and Xcode reuses what the build compiled. The
  build removes the session the CLI stored before its disks are saved.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Authorization
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxCommand

  @prefix "tuist-sandbox-"
  @salt "sandbox command identity"
  @read_scopes ["account:cache:read", "project:cache:read"]
  # Commands run for at most six hours; the token's own expiry is the command's deadline.
  @max_age_seconds 7 * 3600

  @doc """
  The environment `subject`'s command gets in `sandbox`: none outside member
  sandboxes, else the Tuist environment and, when `subject` may use the
  account's cache, `TUIST_OIDC_TOKEN`.
  """
  def env(subject, %Sandbox{} = sandbox, %SandboxCommand{} = command) do
    if credentialed?(subject, sandbox) do
      %Sandbox{account: account} = sandbox = Repo.preload(sandbox, :account)
      env = Sandboxes.tuist_env(account, sandbox)

      case grant(subject, account) do
        nil -> env
        grant -> Map.put(env, "TUIST_OIDC_TOKEN", sign(command, grant))
      end
    else
      %{}
    end
  end

  defp credentialed?(:snapshot_build, sandbox), do: snapshot_builder?(sandbox)
  defp credentialed?(_subject, sandbox), do: Sandboxes.member_sandbox?(sandbox)

  # A builder has its build's id (`DiskSnapshots.start_build/3`).
  defp snapshot_builder?(%Sandbox{id: id, agent_environment_id: agent_environment_id}),
    do:
      is_integer(agent_environment_id) and
        Repo.exists?(
          from(d in DiskSnapshot,
            where: d.id == ^id and d.agent_environment_id == ^agent_environment_id and d.state == :building
          )
        )

  defp grant(:snapshot_build, _account), do: %{"all_projects" => true, "scopes" => @read_scopes}

  defp grant(subject, %Account{} = account) do
    cond do
      Authorization.authorize(:account_cache_create, subject, account) == :ok ->
        Map.put(projects(subject), "scopes", write_scopes(subject))

      Authorization.authorize(:account_cache_read, subject, account) == :ok ->
        Map.put(projects(subject), "scopes", @read_scopes)

      true ->
        nil
    end
  end

  defp write_scopes(%AuthenticatedAccount{scopes: scopes}) do
    held = AccountToken.expand_scopes(scopes)
    Enum.filter(AccountToken.expand_scopes([AccountToken.ci_scope()]), &(&1 in held))
  end

  defp write_scopes(_user), do: [AccountToken.ci_scope()]

  defp projects(%AuthenticatedAccount{all_projects: false, project_ids: project_ids}),
    do: %{"project_ids" => project_ids || []}

  defp projects(_subject), do: %{"all_projects" => true}

  defp sign(command, grant) do
    data = %{
      "command_id" => command.id,
      "sandbox_id" => command.sandbox_id,
      "account_id" => command.account_id,
      "exp" => DateTime.to_unix(command.deadline_at),
      "grant" => grant
    }

    @prefix <> Plug.Crypto.sign(Environment.secret_key_tokens(), @salt, data, max_age: @max_age_seconds)
  end

  @doc "Whether `token` claims to be a sandbox identity token, before it is verified."
  def token?(@prefix <> _token), do: true
  def token?(_token), do: false

  @doc """
  Verifies a sandbox identity token's signature and expiry, returning its
  claims for `account_grant/1` and its expiry as `expires_at`.
  """
  def claims(@prefix <> token) when byte_size(token) <= 16_384 do
    case Plug.Crypto.verify(Environment.secret_key_tokens(), @salt, token, max_age: @max_age_seconds) do
      {:ok, %{"exp" => exp} = claims} ->
        if exp > System.system_time(:second),
          do: {:ok, %{sandbox_command: claims, expires_at: exp}},
          else: {:error, :token_expired}

      {:error, :expired} ->
        {:error, :token_expired}

      {:error, _reason} ->
        {:error, :invalid_token}
    end
  end

  def claims(_token), do: {:error, :invalid_token}

  @doc """
  The account and grant a verified token's command exchanges for, while the
  command still runs in a member sandbox of an account with sandboxes.
  """
  def account_grant(%{
        "command_id" => command_id,
        "sandbox_id" => sandbox_id,
        "account_id" => account_id,
        "grant" => grant
      }) do
    query =
      from s in Sandbox,
        join: c in SandboxCommand,
        on: c.sandbox_id == s.id,
        where:
          s.id == ^sandbox_id and s.account_id == ^account_id and c.id == ^command_id and c.account_id == ^account_id and
            c.status == :running,
        preload: [:account]

    with %Sandbox{account: account} = sandbox <- Repo.one(query),
         true <-
           (Sandboxes.member_sandbox?(sandbox) or snapshot_builder?(sandbox)) and
             Tuist.FeatureFlags.sandboxes_enabled?(account) do
      {:ok, account, grant}
    else
      _ -> {:error, :sandbox_command_not_running}
    end
  end
end
