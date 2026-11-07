defmodule Condukt.CompactorTest do
  use ExUnit.Case, async: true

  alias Condukt.Compactor
  alias Condukt.Compactor.Sliding
  alias Condukt.Message

  describe "compact/3" do
    test "dispatches to a bare module" do
      messages = for i <- 1..30, do: Message.user("m #{i}")
      {:ok, result} = Compactor.compact(Sliding, messages)
      assert length(result) == 20
    end

    test "merges tuple options on top of defaults" do
      messages = for i <- 1..30, do: Message.user("m #{i}")
      {:ok, result} = Compactor.compact({Sliding, keep: 3}, messages)
      assert length(result) == 3
    end
  end
end
