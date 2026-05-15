defmodule Tuist.Application.RuntimeChildrenTest do
  use ExUnit.Case, async: true

  alias Tuist.Application.RuntimeChildren
  alias Tuist.Environment

  describe "guardian_db_sweeper/1" do
    test ":web starts the sweeper" do
      assert [{Guardian.DB.Sweeper, opts}] = RuntimeChildren.guardian_db_sweeper(:web)
      assert Keyword.fetch!(opts, :interval) > 0
    end

    test "every non-web mode returns no children" do
      for mode <- Environment.modes(), mode != :web do
        assert RuntimeChildren.guardian_db_sweeper(mode) == [],
               "expected no Guardian.DB.Sweeper child for #{inspect(mode)} — " <>
                 "non-web pods connect with a DB role that lacks privileges on " <>
                 "`guardian_tokens` and the sweeper would fail every interval " <>
                 "with `permission denied`"
      end
    end
  end
end
