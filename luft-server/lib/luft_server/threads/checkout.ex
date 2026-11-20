defmodule LuftServer.Threads.Checkout do
  @moduledoc "Requests a staged archive, not GitHub credentials, from Tuist."
  alias LuftServer.Threads.Capabilities

  def fits(%{size: size}) when is_integer(size) and size > 4 * 1024 * 1024,
    do: {:error, :repository_too_large}

  def fits(_), do: :ok

  def stage(owner, sandbox, repository, base, _opts \\ []),
    do:
      Capabilities.request(owner, "repository_checkout", %{
        sandbox_id: sandbox.id,
        repository: repository,
        base_sha: base
      })
end
