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

  describe "decode_filters_from_query/2" do
    test "decodes custom tag operators for option filters" do
      available_filters = [
        %Filter.Filter{
          id: "custom_tags",
          field: :custom_tags,
          type: :option,
          options: ["nightly"],
          options_display_names: %{"nightly" => "nightly"},
          operator: :contains,
          value: nil
        }
      ]

      filters =
        Operations.decode_filters_from_query(
          %{"filter_custom_tags_op" => "contains", "filter_custom_tags_val" => "nightly"},
          available_filters
        )

      assert [%Filter.Filter{field: :custom_tags, operator: :contains, value: "nightly"}] = filters
    end
  end
end
