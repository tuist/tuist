defmodule Tuist.ClickHouseRepo do
  @moduledoc """
  Read-only ClickHouse repository for Tuist application.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse,
    read_only: true,
    default_dynamic_repo: Application.compile_env(:tuist, [__MODULE__, :default_dynamic_repo], __MODULE__)

  alias Tuist.ClickHouseRetry

  # `query/3` and `query!/3` are injected by `Ecto.Adapters.ClickHouse`'s
  # own `__before_compile__` callback, which fires after this module's
  # body runs — so they don't exist yet for `defoverridable`. Defer those
  # two overrides to a separate `@before_compile` module that runs after
  # the adapter has planted them.
  @before_compile Tuist.ClickHouseRepo.QueryRetry

  defoverridable aggregate: 2,
                 aggregate: 3,
                 aggregate: 4,
                 all: 1,
                 all: 2,
                 exists?: 1,
                 exists?: 2,
                 one: 1,
                 one: 2,
                 preload: 2,
                 preload: 3

  def all(queryable, opts \\ []), do: ClickHouseRetry.with_retry(fn -> super(queryable, opts) end)

  def one(queryable, opts \\ []), do: ClickHouseRetry.with_retry(fn -> super(queryable, opts) end)

  def exists?(queryable, opts \\ []), do: ClickHouseRetry.with_retry(fn -> super(queryable, opts) end)

  def preload(structs_or_struct_or_nil, preloads, opts \\ []),
    do: ClickHouseRetry.with_retry(fn -> super(structs_or_struct_or_nil, preloads, opts) end)

  # Ecto.Repo `aggregate/3` is overloaded: third arg is `opts` for `:count`
  # and `field` for `:avg/:max/:min/:sum`. Pass through whatever the caller
  # gives us; super dispatches on the original guarded clauses.
  def aggregate(queryable, type, opts_or_field \\ []),
    do: ClickHouseRetry.with_retry(fn -> super(queryable, type, opts_or_field) end)

  def aggregate(queryable, type, field, opts),
    do: ClickHouseRetry.with_retry(fn -> super(queryable, type, field, opts) end)
end
