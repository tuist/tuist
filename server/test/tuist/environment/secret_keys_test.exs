defmodule Tuist.Environment.SecretKeysTest do
  # Not async: the variables below override the secrets passed in, and the
  # development environment sets some of them, so each test clears them.
  use ExUnit.Case, async: false

  alias Tuist.Environment

  @variables ~w(TUIST_SECRET_KEY_BASE TUIST_SECRET_KEY_PASSWORD TUIST_SECRET_KEY_TOKENS)

  setup do
    saved = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(saved, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)
  end

  defp keys(base, password, tokens), do: %{"secret_key" => %{"base" => base, "password" => password, "tokens" => tokens}}

  test "guards hosted production and canary only" do
    assert Environment.secret_keys_guarded?(true, :prod)
    assert Environment.secret_keys_guarded?(true, :can)

    for {hosted?, env} <- [{true, :stag}, {true, :dev}, {true, :test}, {true, :preview}, {false, :prod}, {false, :can}] do
      refute Environment.secret_keys_guarded?(hosted?, env)
    end
  end

  describe "validate_secret_keys!/2" do
    test "accepts three distinct keys in hosted production, and anything elsewhere" do
      assert Environment.validate_secret_keys!(keys("b", "p", "t"), true) == :ok
      assert Environment.validate_secret_keys!(%{"secret_key" => %{"base" => "b"}}, false) == :ok
    end

    test "refuses keys that would fall back to the base, without echoing them" do
      for {secrets, name} <- [
            {%{"secret_key" => %{"base" => "base-value", "tokens" => "t"}}, "TUIST_SECRET_KEY_PASSWORD"},
            {keys("base-value", "p", ""), "TUIST_SECRET_KEY_TOKENS"}
          ] do
        error = assert_raise RuntimeError, fn -> Environment.validate_secret_keys!(secrets, true) end
        assert error.message =~ "#{name} is not set"
        refute error.message =~ "base-value"
      end
    end

    test "refuses a key reused for another purpose" do
      for {secrets, pair} <- [
            {keys("dup-secret", "dup-secret", "t"), "TUIST_SECRET_KEY_BASE and TUIST_SECRET_KEY_PASSWORD"},
            {keys("dup-secret", "p", "dup-secret"), "TUIST_SECRET_KEY_BASE and TUIST_SECRET_KEY_TOKENS"},
            {keys("b", "dup-secret", "dup-secret"), "TUIST_SECRET_KEY_PASSWORD and TUIST_SECRET_KEY_TOKENS"}
          ] do
        error = assert_raise RuntimeError, fn -> Environment.validate_secret_keys!(secrets, true) end
        assert error.message =~ "#{pair} hold the same value"
        refute error.message =~ "dup-secret"
      end
    end
  end
end
