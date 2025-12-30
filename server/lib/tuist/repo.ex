defmodule Tuist.Repo do
  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.Postgres,
    pool_timeout: 15_000

  def timescale_available? do
    query = """
    SELECT EXISTS (
      SELECT 1
      FROM pg_extension
      WHERE extname = 'timescaledb'
    )
    """

    case Ecto.Adapters.SQL.query!(__MODULE__, query, []) do
      %{rows: [[true]]} -> true
      %{rows: [[false]]} -> false
    end
  end

  def running? do
    Enum.member?(Ecto.Repo.all_running(), __MODULE__)
  end

  def connection_pool_metrics do
    # The connection pool is not registered using a name
    # so we need to introspect the repository instance to
    # get the pid of the DB pool.
    #
    # The state looks like this:
    # {:state, {:local, Tuist.Repo}, :one_for_one,
    #  {[DBConnection.ConnectionPool],
    #   %{
    #     DBConnection.ConnectionPool => {:child, #PID<0.3195.0>,
    #      DBConnection.ConnectionPool,
    #      {Ecto.Repo.Supervisor, :start_child,
    #       [
    #         {DBConnection.ConnectionPool, :start_link,
    #          [
    #            {Postgrex.Protocol,
    #             [
    #               types: Postgrex.DefaultTypes,
    #               username: "pepicrft",
    #               port: 5432,
    #               pool: DBConnection.ConnectionPool,
    #               repo: Tuist.Repo,
    #               telemetry_prefix: [:tuist, :repo],
    #               otp_app: :tuist,
    #               timeout: 15000,
    #               hostname: "localhost",
    #               database: "tuist_development",
    #               stacktrace: true,
    #               show_sensitive_data_on_connection_error: true,
    #               pool_size: 10
    #             ]}
    #          ]},
    #         Tuist.Repo,
    #         Ecto.Adapters.Postgres,
    #         %{
    #           opts: [
    #             pool: DBConnection.ConnectionPool,
    #             repo: Tuist.Repo,
    #             timeout: 15000,
    #             pool_size: 10
    #           ],
    #           cache: #Reference<0.3713129610.3042836483.96399>,
    #           stacktrace: true,
    #           repo: Tuist.Repo,
    #           telemetry: {Tuist.Repo, :debug, [:tuist, :repo, :query]},
    #           sql: Ecto.Adapters.Postgres.Connection
    #         }
    #       ]}, :permanent, false, 5000, :worker, [Ecto.Repo.Supervisor]}
    #   }}, :undefined, 0, 5, [], 0, :never, Ecto.Repo.Supervisor,
    #  {Tuist.Repo, Tuist.Repo, :tuist, Ecto.Adapters.Postgres, []}}
    Tuist.Repo
    |> :sys.get_state()
    |> elem(3)
    |> elem(1)
    |> Map.get(DBConnection.ConnectionPool)
    |> elem(1)
    |> DBConnection.ConnectionPool.get_connection_metrics()
    # %{checkout_queue_length: x, ready_conn_count: y}
    |> List.first()
  end
end
