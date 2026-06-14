defmodule TuistRegistryWeb.ConnCase do
  @moduledoc """
  This module defines the test case used by registry controller tests.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias TuistRegistry.CacheArtifact
  alias TuistRegistry.CacheArtifactsBuffer
  alias TuistRegistry.Repo
  alias TuistRegistry.S3Transfer
  alias TuistRegistry.S3TransfersBuffer

  using do
    quote do
      use Oban.Testing, repo: TuistRegistry.Repo
      use TuistRegistryWeb, :verified_routes

      import Phoenix.ConnTest
      import Plug.Conn
      import TuistRegistryWeb.ConnCase

      @endpoint TuistRegistryWeb.Endpoint
    end
  end

  setup _tags do
    :ok = Sandbox.checkout(Repo)

    allow_buffer(CacheArtifactsBuffer)
    allow_buffer(S3TransfersBuffer)

    Repo.delete_all(S3Transfer)
    Repo.delete_all(CacheArtifact)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  defp allow_buffer(buffer) do
    if pid = Process.whereis(buffer) do
      Sandbox.allow(Repo, self(), pid)
      buffer.reset()
    end
  end
end
