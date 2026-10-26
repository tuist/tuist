defmodule Atlas.Automations.JavaScriptTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Automations.JavaScript

  test "source size is bounded before compilation" do
    assert {:error, "JavaScript source exceeds 64 KiB."} = JavaScript.evaluate(String.duplicate("x", 65_537), %{})
  end

  @tag skip: match?({:unix, :linux}, :os.type())
  test "unsupported platforms fail closed without an in-process fallback" do
    assert JavaScript.child_spec() == nil

    assert {:error, "Untrusted JavaScript requires the Linux isolated executor."} =
             JavaScript.evaluate("return input;", %{})
  end

  @tag skip: not match?({:unix, :linux}, :os.type()), timeout: 120_000
  test "isolated JavaScript computes JSON and rejects runaway or invalid output" do
    expect(Javex, :compile, 5, fn source, opts ->
      result = Mimic.call_original(Javex, :compile, [source, opts])
      assert {:ok, _} = result
      result
    end)

    expect(Javex, :run, 5, fn compiled, input, opts ->
      result = Mimic.call_original(Javex, :run, [compiled, input, opts])
      if input == %{"value" => 4}, do: assert({:ok, %{"double" => 8}} = result)
      result
    end)

    assert {:ok, %{"double" => 8}} = JavaScript.evaluate("return {double: input.value * 2};", %{"value" => 4})
    assert {:error, _} = JavaScript.evaluate("while (true) {}", %{})
    assert {:error, _} = JavaScript.evaluate("return undefined;", %{})
    assert {:error, _} = JavaScript.evaluate("return {token: process.env.SECRET};", %{})
    assert {:error, _} = JavaScript.evaluate("return fetch('https://example.com');", %{})
  end
end
