defmodule Credo.Checks.UnusedReturnValueTest do
  use Credo.Test.Case

  alias Credo.Checks.UnusedReturnValue

  describe "Repo.insert" do
    test "when return value is unused, it should report a violation" do
      """
      defmodule Example do
        def create_user(attrs) do
          Tuist.Repo.insert(%User{name: attrs.name})
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(UnusedReturnValue)
      |> assert_issue()
    end

    test "when return value is unused with aliased module, it should report a violation" do
      """
      defmodule Example do
        alias Tuist.Repo

        def create_user(attrs) do
          Repo.insert(%User{name: attrs.name})
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(UnusedReturnValue)
      |> assert_issue()
    end

    test "when return value is matched, it should not report a violation" do
      """
      defmodule Example do
        def create_user(attrs) do
          {:ok, _} = Tuist.Repo.insert(%User{name: attrs.name})
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(UnusedReturnValue)
      |> refute_issues()
    end

    test "when return value is returned, it should not report a violation" do
      """
      defmodule Example do
        def create_user(attrs) do
          Tuist.Repo.insert(%User{name: attrs.name})
        end
      end
      """
      |> to_source_file()
      |> run_check(UnusedReturnValue)
      |> refute_issues()
    end

    test "when return value is used in with, it should not report a violation" do
      """
      defmodule Example do
        def create_user(attrs) do
          with {:ok, user} <- Tuist.Repo.insert(%User{name: attrs.name}) do
            {:ok, user}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(UnusedReturnValue)
      |> refute_issues()
    end
  end

  describe "Repo.transaction" do
    test "when return value is unused, it should report a violation" do
      """
      defmodule Example do
        def do_work do
          Tuist.Repo.transaction(fn -> :work end)
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(UnusedReturnValue)
      |> assert_issue()
    end
  end

  describe "Oban.insert" do
    test "when return value is unused, it should report a violation" do
      """
      defmodule Example do
        def enqueue_job do
          Oban.insert(MyWorker.new(%{id: 1}))
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(UnusedReturnValue)
      |> assert_issue()
    end

    test "when return value is matched, it should not report a violation" do
      """
      defmodule Example do
        def enqueue_job do
          {:ok, _job} = Oban.insert(MyWorker.new(%{id: 1}))
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(UnusedReturnValue)
      |> refute_issues()
    end
  end
end
