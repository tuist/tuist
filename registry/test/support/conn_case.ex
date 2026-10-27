defmodule TuistRegistryWeb.ConnCase do
  @moduledoc """
  This module defines the test case used by registry controller tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use TuistRegistryWeb, :verified_routes

      import Phoenix.ConnTest
      import Plug.Conn
      import TuistRegistryWeb.ConnCase

      @endpoint TuistRegistryWeb.Endpoint
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
