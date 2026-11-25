defmodule Tuist.Environment.EncryptionKeysTest do
  # Not async: the variables below override the secrets passed in, and the
  # development environment sets some of them, so each test clears them.
  use ExUnit.Case, async: false

  alias Tuist.Environment

  @variables ~w(
    TUIST_SECRET_KEY_BASE
    TUIST_SECRET_KEY_ENCRYPTION
    TUIST_SECRET_KEY_ENCRYPTION_KEYS
    TUIST_SECRET_KEY_ENCRYPTION_CURRENT_KEY
    TUIST_SECRET_KEY_ENCRYPTION_KEY_IDS
  )

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

  test "derives the single key exactly as before the key ring, so values stored under it stay readable" do
    long = "0123456789abcdef0123456789abcdef-tail"

    assert Environment.encryption_keys(%{"secret_key" => %{"encryption" => long}}, false) ==
             [{"V1", "0123456789abcdef0123456789abcdef"}]

    assert Environment.encryption_keys(%{"secret_key" => %{"encryption" => "short"}}, false) ==
             [{"V1", "short" <> :binary.copy(<<0>>, 27)}]

    assert Environment.encryption_keys(%{"secret_key" => %{"base" => long}}, false) ==
             [{"V1", "0123456789abcdef0123456789abcdef"}]
  end

  test "encrypts with the ring's first key by default and keeps the single key as a retired V1" do
    key_a = :crypto.strong_rand_bytes(32)
    key_b = :crypto.strong_rand_bytes(32)
    legacy = String.duplicate("l", 32)
    ring = "b:#{Base.encode64(key_b)}, a:#{Base.encode64(key_a)}"
    secrets = %{"secret_key" => %{"encryption" => legacy, "encryption_keys" => ring}}

    assert Environment.encryption_keys(secrets, false) == [{"b", key_b}, {"a", key_a}, {"V1", legacy}]

    assert Environment.encryption_keys(put_in(secrets, ["secret_key", "encryption_current_key"], "V1"), false) ==
             [{"V1", legacy}, {"b", key_b}, {"a", key_a}]

    assert Environment.encryption_keys(put_in(secrets, ["secret_key", "encryption_current_key"], "a"), false) ==
             [{"a", key_a}, {"b", key_b}, {"V1", legacy}]
  end

  test "refuses a malformed ring or an unknown current key without echoing key material" do
    key = Base.encode64(:crypto.strong_rand_bytes(32))

    for ring <- ["a:#{Base.encode64("short")}", "a:#{key},a:#{key}", "V1:#{key}", ":#{key}", "a b:#{key}", ","] do
      error =
        assert_raise RuntimeError, fn ->
          Environment.encryption_keys(%{"secret_key" => %{"encryption_keys" => ring}}, false)
        end

      refute error.message =~ key
      refute error.message =~ Base.encode64("short")
    end

    assert_raise RuntimeError, ~r/"c", which is not a configured/, fn ->
      Environment.encryption_keys(
        %{"secret_key" => %{"encryption_keys" => "a:#{key}", "encryption_current_key" => "c"}},
        false
      )
    end
  end

  test "hosted production requires an explicit, full-length current key distinct from secret_key_base" do
    base = String.duplicate("b", 64)
    key = :crypto.strong_rand_bytes(32)
    ring = "k1:#{Base.encode64(key)}"

    assert_raise RuntimeError, ~r/Set TUIST_SECRET_KEY_ENCRYPTION_KEYS/, fn ->
      Environment.encryption_keys(%{"secret_key" => %{"base" => base}}, true)
    end

    assert_raise RuntimeError, ~r/derived from TUIST_SECRET_KEY_BASE/, fn ->
      Environment.encryption_keys(%{"secret_key" => %{"base" => base, "encryption" => base}}, true)
    end

    assert_raise RuntimeError, ~r/zero-padded/, fn ->
      Environment.encryption_keys(%{"secret_key" => %{"base" => base, "encryption" => "short"}}, true)
    end

    assert_raise RuntimeError, ~r/derived from TUIST_SECRET_KEY_BASE/, fn ->
      Environment.encryption_keys(
        %{"secret_key" => %{"base" => base, "encryption_keys" => "k1:#{Base.encode64(binary_part(base, 0, 32))}"}},
        true
      )
    end

    # The base no longer backs a ring as a hidden V1 key, but an explicit
    # single key equal to it stays readable while values move off it.
    assert Environment.encryption_keys(%{"secret_key" => %{"base" => base, "encryption_keys" => ring}}, true) ==
             [{"k1", key}]

    assert Environment.encryption_keys(
             %{"secret_key" => %{"base" => base, "encryption" => base, "encryption_keys" => ring}},
             true
           ) == [{"k1", key}, {"V1", binary_part(base, 0, 32)}]

    distinct = String.duplicate("e", 40)

    assert Environment.encryption_keys(%{"secret_key" => %{"base" => base, "encryption" => distinct}}, true) ==
             [{"V1", binary_part(distinct, 0, 32)}]
  end

  test "refuses to boot without every key id the deployment lists, naming only the ids" do
    key = :crypto.strong_rand_bytes(32)
    secrets = %{"secret_key" => %{"encryption" => String.duplicate("l", 32), "encryption_key_ids" => "V1, k2"}}

    error = assert_raise RuntimeError, fn -> Environment.encryption_keys(secrets, false) end
    assert error.message =~ "lists k2, which this node has no key for"

    secrets = put_in(secrets, ["secret_key", "encryption_keys"], "k2:#{Base.encode64(key)}")
    assert [{"k2", ^key}, {"V1", _legacy}] = Environment.encryption_keys(secrets, false)
  end

  test "derives V1 from secret_key_base until the required key ids retire it" do
    key = :crypto.strong_rand_bytes(32)
    base = String.duplicate("b", 64)
    secrets = %{"secret_key" => %{"base" => base, "encryption_keys" => "k2:#{Base.encode64(key)}"}}
    derived = binary_part(base, 0, 32)

    # Mid-rotation: values stored under the base-derived key must stay readable.
    assert Environment.encryption_keys(secrets, false) == [{"k2", key}, {"V1", derived}]

    assert Environment.encryption_keys(put_in(secrets, ["secret_key", "encryption_key_ids"], "k2, V1"), false) ==
             [{"k2", key}, {"V1", derived}]

    assert Environment.encryption_keys(put_in(secrets, ["secret_key", "encryption_key_ids"], "k2"), false) ==
             [{"k2", key}]

    # An explicit single key is configuration, not a fallback: it stays.
    explicit = put_in(secrets, ["secret_key", "encryption"], String.duplicate("l", 32))

    assert Environment.encryption_keys(put_in(explicit, ["secret_key", "encryption_key_ids"], "k2"), false) ==
             [{"k2", key}, {"V1", String.duplicate("l", 32)}]
  end
end
