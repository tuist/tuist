defmodule Noora.FilterTest do
  use ExUnit.Case, async: true

  alias Noora.Filter
  alias Noora.Filter.Operations

  describe "convert_filters_to_flop/1" do
    test "converts Noora negative text filters into Flop operators" do
      # When
      got =
        Operations.convert_filters_to_flop([
          %Filter.Filter{id: "module_name", field: :module_name, operator: :"!=~", value: "UITests"},
          %Filter.Filter{id: "status", field: :status, operator: :==, value: "success"}
        ])

      # Then
      assert [
               %{field: :module_name, op: :not_ilike, value: "UITests"},
               %{field: :status, op: :==, value: "success"}
             ] = got
    end
  end
end
