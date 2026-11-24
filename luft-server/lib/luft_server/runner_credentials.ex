defmodule LuftServer.RunnerCredentials do
  @moduledoc "Machine credentials issued by Luft, bound to the registering Luft session."

  import Ecto.Query

  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Threads.Runner
  alias LuftServerWeb.Endpoint

  @salt "luft runner v1"
  @local_salt "luft local runner v1"

  defmodule Binding do
    @moduledoc false
    use Ecto.Schema

    @primary_key false
    schema "thread_runner_credentials" do
      field :runner_id, :binary_id, primary_key: true
      field :session_id, :binary_id
    end
  end

  @doc "Issues a local machine secret; only its hash may be persisted."
  def issue(session) do
    "luft_runner_local_" <>
      Phoenix.Token.encrypt(Endpoint, @local_salt, {session.id, :crypto.strong_rand_bytes(32)})
  end

  def wrap(token, session) do
    "luft_runner_" <> Phoenix.Token.encrypt(Endpoint, @salt, {session.id, token})
  end

  # Preserve the existing Authenticate contract: for local runners its
  # :runner_token assign is the local credential, never an upstream token.
  def resolve("luft_runner_local_" <> encrypted = token) do
    with {:ok, {id, _secret}} <-
           Phoenix.Token.decrypt(Endpoint, @local_salt, encrypted, max_age: 2_592_000),
         %{} = session <- Sessions.get_by_id(id),
         true <-
           Repo.exists?(
             from(binding in Binding,
               join: runner in Runner,
               on: runner.id == binding.runner_id,
               where:
                 binding.session_id == ^id and is_nil(runner.revoked_at) and
                   runner.token_hash == ^:crypto.hash(:sha256, token)
             ),
             log: false
           ) do
      {:ok, session, token}
    else
      _ -> :error
    end
  end

  def resolve("luft_runner_" <> encrypted) do
    with {:ok, {id, token}} <-
           Phoenix.Token.decrypt(Endpoint, @salt, encrypted, max_age: 2_592_000),
         %{} = session <- Sessions.get_by_id(id) do
      {:ok, session, token}
    else
      _ -> :error
    end
  end

  def resolve(_token), do: :error
end
