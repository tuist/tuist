defmodule Tuist.Sandboxes.Workspaces do
  @moduledoc "Account-scoped, replayable workspace allocation; no conversation identities."

  import Ecto.Query, only: [from: 2]

  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Commands
  alias Tuist.Sandboxes.ProviderEnvironment
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxCommand

  def ensure(account, key) do
    case Ecto.UUID.cast(key) do
      {:ok, key} ->
        Repo.checkout(
          fn ->
            lock = "sandbox-workspace:#{account.id}:#{key}"

            case Repo.query!("SELECT pg_try_advisory_lock(hashtextextended($1, 0))", [lock]).rows do
              [[true]] ->
                try do
                  allocate(account, key)
                after
                  Repo.query!("SELECT pg_advisory_unlock(hashtextextended($1, 0))", [lock])
                end

              _ ->
                {:error, :workspace_busy}
            end
          end,
          timeout: :infinity
        )

      _ ->
        {:error, :invalid_request}
    end
  end

  def fetch(account, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Sandbox{account_id: account_id, purpose: :agent} = sandbox <- Repo.get(Sandbox, id),
         true <- account_id == account.id do
      {:ok, sandbox}
    else
      _ -> {:error, :not_found}
    end
  end

  def forget_command(sandbox, id) do
    Repo.delete_all(from c in SandboxCommand, where: c.id == ^id and c.sandbox_id == ^sandbox.id and c.status != :running)
    {:ok, %{}}
  end

  def watch_command(sandbox, id, wait) do
    case Repo.get_by(SandboxCommand, id: id, sandbox_id: sandbox.id) do
      %SandboxCommand{status: status} = command when status != :running -> {:ok, Commands.serialize(command)}
      %SandboxCommand{} when sandbox.state == :running -> Commands.wait(sandbox, id, wait)
      %SandboxCommand{} -> {:ok, %{status: "running"}}
      nil -> {:error, :not_found}
    end
  end

  defp allocate(account, key) do
    external = "workspaces/#{key}"

    binding =
      Repo.get_by(ProviderEnvironment, account_id: account.id, external_key: external) ||
        Repo.insert!(%ProviderEnvironment{account_id: account.id, external_key: external})

    case Repo.get_by(Sandbox, provider_environment_id: binding.id) do
      nil ->
        Sandboxes.create_sandbox(account, %{provider_environment_id: binding.id})

      %Sandbox{state: :error, last_active_at: nil, archive_key: nil} = sandbox ->
        with {:ok, _} <- Sandboxes.delete(sandbox),
             do: Sandboxes.create_sandbox(account, %{provider_environment_id: binding.id})

      sandbox ->
        {:ok, sandbox}
    end
  end
end
