defmodule ScaleEndToEnd do
  @moduledoc false
  alias Tuist.Accounts.User
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  def boot(port) do
    Application.put_env(:esbuild, :version_check, false)
    Application.put_env(:bcrypt_elixir, :log_rounds, 12)
    Application.put_env(:ex_aws, :secret_access_key, "testpassword")
    Application.put_env(:ex_aws, :s3, scheme: "http://", host: "127.0.0.1", port: 14_103, region: "us-east-1")

    for repo <- [Tuist.Repo, Tuist.IngestRepo] do
      config =
        :tuist
        |> Application.get_env(repo)
        |> Keyword.put(:pool, DBConnection.ConnectionPool)
        |> Keyword.put(:pool_size, 2)

      config =
        if repo == Tuist.Repo,
          do:
            Keyword.merge(config,
              hostname: "127.0.0.1",
              port: "TUIST_E2E_POSTGRES_PORT" |> System.get_env("14106") |> String.to_integer(),
              username: System.get_env("TUIST_E2E_POSTGRES_USER", "scale_e2e"),
              password: System.get_env("TUIST_E2E_POSTGRES_PASSWORD")
            ),
          else: config

      Application.put_env(:tuist, repo, config)
    end

    endpoint =
      :tuist
      |> Application.get_env(TuistWeb.Endpoint)
      |> Keyword.put(:server, true)
      |> Keyword.put(:http, ip: {127, 0, 0, 1}, port: port)

    Application.put_env(:tuist, TuistWeb.Endpoint, endpoint)
    Application.put_env(:tuist, Tuist.Tasks, sync: false)
    :inet_db.res_option(:resolv_conf, ~c"")
    :inet_db.res_option(:nameservers, [{{127, 0, 0, 1}, 15_353}])

    Application.put_env(:libcluster, :topologies,
      e2e: [
        strategy: Cluster.Strategy.Kubernetes.DNS,
        config: [service: "tuist-e2e.local", application_name: "tuist_e2e", polling_interval: 200]
      ]
    )

    {:ok, _} = Application.ensure_all_started(:tuist)

    Logger.configure(level: :warning)
    {:ok, _} = Supervisor.start_child(Tuist.Supervisor, Tuist.Marketing.Stats)
    IO.puts("Full server #{port} booted; discovery=#{inspect(:inet_res.getbyname(~c"tuist-e2e.local", :a))}")
  end

  defp random_id, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

  defp unique_user do
    handle = "e2e-" <> random_id()
    AccountsFixtures.user_fixture(email: handle <> "@example.com", handle: handle, customer_id: nil)
  end

  def seed do
    user = unique_user()
    {user.id, user.token, user.account.name}
  end

  def cache_credentials do
    user = unique_user()
    project = ProjectsFixtures.project_fixture(account: user.account)
    project_value = Tuist.Projects.create_project_token(project)
    {:ok, project_token} = Tuist.Projects.get_project_token(project_value)

    {:ok, {account_token, account_value}} =
      Tuist.Accounts.create_account_token(%{
        account: user.account,
        name: "load-test",
        scopes: ["project:cache:read"]
      })

    {project_token, project_value, account_token, account_value}
  end

  def many_cache_credentials(count) do
    user = unique_user()
    project = ProjectsFixtures.project_fixture(account: user.account)

    values =
      Enum.flat_map(1..count, fn n ->
        project_value = Tuist.Projects.create_project_token(project)

        {:ok, {_token, account_value}} =
          Tuist.Accounts.create_account_token(%{
            account: user.account,
            name: "diverse-load-#{n}",
            scopes: ["project:cache:read"]
          })

        [project_value, account_value]
      end)

    {user.id, project.id, values}
  end

  def revoke_cache_credentials(project_token, account_token) do
    {:ok, _} = Tuist.Projects.revoke_project_token(project_token)
    {:ok, _} = Tuist.Accounts.delete_account_token(account_token)
    :ok
  end

  def permission_subject do
    owner = unique_user()
    member = unique_user()
    organization = AccountsFixtures.organization_fixture(creator: owner, customer_id: nil, name: "e2e-" <> random_id())
    :ok = Tuist.Accounts.add_user_to_organization(member, organization)

    project =
      ProjectsFixtures.project_fixture(
        account: organization.account,
        name: "e2e-" <> random_id()
      )

    {member.id, member.token, organization.id, organization.account.name, project.name}
  end

  def revoke_membership(user_id, organization_id) do
    user = Tuist.Repo.get!(User, user_id)
    organization = Tuist.Repo.get!(Tuist.Accounts.Organization, organization_id)
    Tuist.Accounts.remove_user_from_organization(user, organization)
    :ok
  end

  def pending_task(path) do
    Tuist.Tasks.run_async(fn ->
      Process.sleep(500)
      File.write!(path, "completed")
    end)
  end

  def revoke(id) do
    User |> Tuist.Repo.get!(id) |> Ecto.Changeset.change(token: "revoked-" <> random_id()) |> Tuist.Repo.update!()
    :ok
  end
end

defmodule ScaleEndToEndObserver do
  @moduledoc false
  alias Tuist.Marketing.OpenGraph

  def start do
    Code.ensure_loaded!(OpenGraph)
    Code.ensure_loaded!(Bcrypt)
    :erlang.trace(:all, false, [:call, :set_on_spawn])
    pid = spawn(__MODULE__, :loop, [%{}])
    :erlang.trace_pattern({OpenGraph, :generate_og_image_binary, 1}, true, [:local])
    :erlang.trace_pattern({Bcrypt, :verify_pass, 2}, true, [:local])
    :erlang.trace(:all, true, [:call, :set_on_spawn, {:tracer, pid}])
    pid
  end

  def loop(counts) do
    receive do
      {:trace, _, :call, {OpenGraph, :generate_og_image_binary, [title]}} ->
        loop(Map.update(counts, title, 1, &(&1 + 1)))

      {:trace, _, :call, {Bcrypt, :verify_pass, _}} ->
        loop(Map.update(counts, :bcrypt, 1, &(&1 + 1)))

      {:count, caller, ref, title} ->
        send(caller, {ref, Map.get(counts, title, 0)})
        loop(counts)

      _ ->
        loop(counts)
    end
  end

  def count(pid, title) do
    delivered = :erlang.trace_delivered(:all)

    receive do
      {:trace_delivered, :all, ^delivered} -> :ok
    after
      5_000 -> raise "trace delivery timed out"
    end

    ref = make_ref()
    send(pid, {:count, self(), ref, title})

    receive do
      {^ref, count} -> count
    after
      1000 -> raise "render observer timed out"
    end
  end
end
