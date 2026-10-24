defmodule Atlas.Orbit.RenderingTest do
  use ExUnit.Case, async: true

  alias Atlas.Orbit.Rendering

  test "oversized account evidence remains valid JSON with bounded card fields" do
    result = %{
      account: %{
        name: "Northstar",
        primary_domain: "northstar.example",
        status: "active",
        segment: "enterprise",
        description: String.duplicate("Long account context. ", 500),
        token: "never-display"
      },
      contacts: for(index <- 1..30, do: %{name: "Contact #{index}", email: "person#{index}@example.org"})
    }

    rendered = Rendering.output(result, "get_account")
    assert String.length(rendered) <= 4_000
    assert {:ok, summary} = JSON.decode(rendered)

    assert summary["account"] == %{
             "name" => "Northstar",
             "primary_domain" => "northstar.example",
             "status" => "active",
             "segment" => "enterprise"
           }

    assert summary["truncated"]
    assert summary["notice"] =~ "omitted"
    refute rendered =~ "never-display"
    refute rendered =~ "person1@example.org"
    assert Rendering.for_model(result) =~ "person1@example.org"
  end

  test "JSON escapes and multibyte fields cannot exceed the evidence budget" do
    for text <- [
          String.duplicate("\n\u0001\"\\", 2_000),
          String.duplicate("🌍", 5_000),
          "a" <> String.duplicate("\u0301", 5_000)
        ] do
      result = %{
        account: Map.new(~w(name primary_domain status segment deal_stage legal_name), &{&1, text})
      }

      rendered = Rendering.output(result, "get_account")
      assert String.length(rendered) <= 4_000
      assert byte_size(rendered) <= 4_000
      assert {:ok, %{"account" => account, "truncated" => true}} = JSON.decode(rendered)
      assert Enum.all?(Map.values(account), &(String.length(&1) <= 80))
    end
  end

  test "small account evidence retains full redacted source and ordinary results keep their existing bound" do
    result = %{
      account: %{name: "Northstar", token: "never-display"},
      contacts: [%{name: "Taylor"}]
    }

    assert Rendering.output(result, "get_account") == Rendering.output(result)

    assert {:ok, %{"account" => %{"token" => "[redacted]"}, "contacts" => [_]}} =
             JSON.decode(Rendering.output(result))

    assert String.length(Rendering.output(String.duplicate("x", 5_000), "other_tool")) == 4_000

    assert String.length(Rendering.output(%{account: nil, body: String.duplicate("x", 5_000)}, "get_account")) == 4_000
  end
end
