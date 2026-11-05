defmodule PulseWeb.ConnCase do
  @moduledoc "HTTP tests with owned dependencies and service instances."
  use ExUnit.CaseTemplate

  alias Pulse.Test.Case

  using do
    quote do
      use PulseWeb, :verified_routes

      import Case, only: [start_supervised: 1, start_supervised: 2, start_supervised!: 1, start_supervised!: 2]

      import ExUnit.Callbacks,
        except: [start_supervised: 1, start_supervised: 2, start_supervised!: 1, start_supervised!: 2]

      import Phoenix.ConnTest
      import Plug.Conn
      import PulseWeb.ConnCase

      @endpoint PulseWeb.Endpoint
    end
  end

  setup tags do
    {:ok, context} = Case.setup_runtime(tags)
    {:ok, Map.put(Map.new(context), :conn, Phoenix.ConnTest.build_conn())}
  end
end
