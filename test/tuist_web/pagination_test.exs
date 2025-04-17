defmodule TuistWeb.FlopTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Flop

  describe "get_options_with_before_and_after/2" do
    test "puts last if before is specified" do
      # When
      got = Flop.get_options_with_before_and_after(%{}, before: "cursor")

      # Then
      assert got == %{last: 20, before: "cursor"}
    end

    test "puts first if after is specified" do
      # When
      got = Flop.get_options_with_before_and_after(%{}, after: "cursor")

      # Then
      assert got == %{first: 20, after: "cursor"}
    end

    test "puts first if neither before nor after is specified" do
      # When
      got = Flop.get_options_with_before_and_after(%{}, some_other_key: false)

      # Then
      assert got == %{first: 20}
    end
  end
end
