defmodule SlackWeb.ConnCase do
  @moduledoc """
  Test case for tests that need an HTTP connection and database access.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use SlackWeb, :verified_routes

      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn
      import SlackWeb.ConnCase

      @endpoint SlackWeb.Endpoint
    end
  end

  setup tags do
    Slack.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
