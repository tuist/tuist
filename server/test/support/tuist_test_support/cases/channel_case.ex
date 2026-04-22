defmodule TuistWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.

  Such tests rely on `Phoenix.ChannelTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use TuistWeb.ChannelCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using options do
    clickhouse? = Keyword.get(options, :clickhouse, false)
    async? = Keyword.get(options, :async, false)

    if clickhouse? and async? do
      raise ArgumentError,
            "ClickHouse tests cannot be async. Use `use TuistWeb.ChannelCase, clickhouse: true` without `async: true`."
    end

    quote bind_quoted: [clickhouse?: clickhouse?] do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import TuistWeb.ChannelCase

      # The default endpoint for testing
      @endpoint TuistWeb.Endpoint

      if clickhouse?, do: @moduletag(:clickhouse)
    end
  end

  setup tags do
    TuistTestSupport.Cases.DataCase.setup_sandbox(tags)

    if tags[:clickhouse] do
      on_exit(fn ->
        TuistTestSupport.Utilities.truncate_clickhouse_tables()
      end)
    end

    :ok
  end
end
