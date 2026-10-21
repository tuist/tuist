defmodule Atlas.NativeThemesTest do
  use ExUnit.Case, async: true

  alias Atlas.NativeThemes

  test "companies can replace the catalog and default without a client release" do
    defaults = NativeThemes.catalog(nil)
    assert {:ok, ^defaults} = NativeThemes.validate(defaults)

    theme = defaults["themes"] |> hd() |> Map.merge(%{"id" => "northstar", "name" => "Northstar"})

    company = %{
      defaults
      | "revision" => "company-2",
        "default_theme_id" => "northstar",
        "themes" => [theme]
    }

    assert NativeThemes.catalog(company) == company
  end

  test "invalid versions, defaults, duplicate IDs, and unreadable colors fall back safely" do
    defaults = NativeThemes.catalog(nil)

    for invalid <- [
          %{defaults | "schema_version" => 2},
          %{defaults | "default_theme_id" => "missing"},
          %{defaults | "themes" => defaults["themes"] ++ defaults["themes"]},
          put_in(defaults, ["themes", Access.at(0), "id"], "server-default"),
          %{
            defaults
            | "default_theme_id" => "company\n",
              "themes" => [defaults["themes"] |> hd() |> Map.put("id", "company\n")]
          },
          put_in(defaults, ["themes", Access.at(0), "light", "secondary_text"], "#FFFFFF\n"),
          put_in(defaults, ["themes", Access.at(0), "light", "secondary_text"], "#FFFFFF"),
          put_in(defaults, ["themes", Access.at(0), "dark", "on_accent"], "#8EDBD2")
        ] do
      assert NativeThemes.catalog(invalid) == defaults
    end
  end
end
