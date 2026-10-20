defmodule Atlas.Inference.ProviderTest do
  use Atlas.DataCase, async: true

  alias Atlas.Inference.Provider

  test "decision paths stay relative to the configured provider endpoint" do
    attrs = %{key: "typesafe", base_url: "https://api.typesafe.ai/v1"}

    for path <- [nil, "", "systemone", "alpha/decisions"] do
      assert Provider.changeset(%Provider{}, Map.put(attrs, :decision_path, path)).valid?
    end

    for path <- [
          "https://other.example/decisions",
          "/systemone",
          "../decisions",
          "systemone?key=secret",
          "systemone#fragment"
        ] do
      refute Provider.changeset(%Provider{}, Map.put(attrs, :decision_path, path)).valid?
    end
  end
end
