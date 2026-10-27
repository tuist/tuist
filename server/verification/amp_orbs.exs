# Run with MIX_ENV=test mix run --no-start verification/amp_orbs.exs.
# The caller owns these disposable databases and the private output directory.
defmodule AmpOrbVerification do
  @moduledoc false
  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Repo
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias TuistWeb.Endpoint

  def run do
    true = Mix.env() == :test
    config = Application.fetch_env!(:tuist, Repo)
    true = config[:hostname] in ["localhost", "127.0.0.1"]
    true = String.starts_with?(config[:database], "tuist_amp_orbs_")
    directory = System.fetch_env!("TUIST_ORB_VALIDATION_DIR")
    true = File.dir?(directory)

    Application.put_env(:tuist, Repo, Keyword.merge(config, pool: DBConnection.ConnectionPool, pool_size: 10))
    Application.put_env(:tuist, Endpoint, Keyword.put(Application.fetch_env!(:tuist, Endpoint), :server, true))
    {:ok, _} = Application.ensure_all_started(:tuist)
    Logger.configure(level: :warning)

    handle = "orb-validation-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, user} = Accounts.create_user(handle <> "@example.invalid", handle: handle)
    {:ok, _} = FunWithFlags.enable(:sandboxes, for_actor: user.account)
    {:ok, token, _} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token", ttl: {2, :hour})

    # Only the local dispatch process reads this file; never include it in artifacts.
    path = Path.join(directory, "provider.env")
    File.write!(path, "export TUIST_ACCOUNT=#{handle}\nexport TUIST_TOKEN=#{token}\n")
    File.chmod!(path, 0o600)
    verify_authorization(user, token)
    IO.puts("Isolated Tuist API ready; account #{handle}")
    observe(directory, user.account.id, nil)
  end

  defp verify_authorization(user, token) do
    port = Endpoint.config(:http)[:port]
    url = "http://127.0.0.1:#{port}/api/accounts/#{user.account.name}/sandboxes/amp-orbs/amp-missing"
    options = [json: %{operation: "pause"}, retry: false]
    %{status: 401} = Req.post!(url, options)
    %{status: 204} = Req.post!(url, Keyword.put(options, :auth, {:bearer, token}))

    {:ok, outsider} = Accounts.create_user("outsider-#{user.id}@example.invalid", handle: "outsider-#{user.id}")
    {:ok, outsider_token, _} = Tuist.Guardian.encode_and_sign(outsider, %{}, token_type: "access_token")
    %{status: 403} = Req.post!(url, Keyword.put(options, :auth, {:bearer, outsider_token}))
    IO.puts("PASS: real HTTP authentication and account-admin authorization (401/204/403).")
  end

  defp observe(directory, account_id, previous) do
    sandboxes =
      Repo.all(from(s in Sandbox, where: s.account_id == ^account_id and not is_nil(s.amp_orb_id)))

    state = %{
      nodes: Enum.map(Nodes.connected_nodes(), & &1.name),
      sandboxes: Enum.map(sandboxes, &Map.take(&1, [:id, :amp_orb_id, :state, :residency_work_id, :residency_epoch]))
    }

    if state != previous do
      json = JSON.encode!(state)
      File.write!(Path.join(directory, "state.json.tmp"), json)
      File.rename!(Path.join(directory, "state.json.tmp"), Path.join(directory, "state.json"))
      IO.puts(json)
    end

    Process.sleep(1_000)
    observe(directory, account_id, state)
  end
end

AmpOrbVerification.run()
