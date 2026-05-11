defmodule Tuist.ClickHouseRepo.QueryRetry do
  @moduledoc """
  `@before_compile` hook for `Tuist.ClickHouseRepo` that wraps
  `query/3` and `query!/3` with `Tuist.ClickHouseRetry.with_retry/1`.

  These two functions are injected by `Ecto.Adapters.ClickHouse`'s own
  `__before_compile__`, so they cannot be `defoverridable`d from the
  repo module body. Running this hook from a separate module ensures
  Elixir can resolve the macro at compile time and that the adapter's
  injection has already happened by the time we override.
  """

  defmacro __before_compile__(_env) do
    quote do
      defoverridable query: 1, query: 2, query: 3, query!: 1, query!: 2, query!: 3

      def query(sql, params \\ [], opts \\ []), do: Tuist.ClickHouseRetry.with_retry(fn -> super(sql, params, opts) end)

      def query!(sql, params \\ [], opts \\ []), do: Tuist.ClickHouseRetry.with_retry(fn -> super(sql, params, opts) end)
    end
  end
end
