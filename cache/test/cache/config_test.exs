defmodule Cache.ConfigTest do
  use ExUnit.Case, async: false

  describe "s3_protocols/0" do
    setup do
      original = Application.get_env(:cache, :s3)
      on_exit(fn -> Application.put_env(:cache, :s3, original) end)
      %{original_s3: original}
    end

    test "returns protocols from app config", %{original_s3: original} do
      Application.put_env(:cache, :s3, Keyword.put(original || [], :protocols, [:http1]))

      assert Cache.Config.s3_protocols() == [:http1]
    end

    test "returns http2 protocol when configured", %{original_s3: original} do
      Application.put_env(:cache, :s3, Keyword.put(original || [], :protocols, [:http2]))

      assert Cache.Config.s3_protocols() == [:http2]
    end

    test "defaults to [:http2, :http1] when protocols not set", %{original_s3: original} do
      Application.put_env(:cache, :s3, Keyword.delete(original || [], :protocols))

      assert Cache.Config.s3_protocols() == [:http2, :http1]
    end

    test "defaults to [:http2, :http1] when protocols is empty list", %{original_s3: original} do
      Application.put_env(:cache, :s3, Keyword.put(original || [], :protocols, []))

      assert Cache.Config.s3_protocols() == [:http2, :http1]
    end

    test "defaults to [:http2, :http1] when s3 config is nil" do
      Application.put_env(:cache, :s3, nil)

      assert Cache.Config.s3_protocols() == [:http2, :http1]
    end
  end

  describe "s3_virtual_host/0" do
    setup do
      original = Application.get_env(:ex_aws, :s3)
      on_exit(fn -> Application.put_env(:ex_aws, :s3, original) end)
      %{original_ex_aws_s3: original}
    end

    test "returns true when virtual_host is true", %{original_ex_aws_s3: original} do
      Application.put_env(:ex_aws, :s3, Keyword.put(original || [], :virtual_host, true))

      assert Cache.Config.s3_virtual_host() == true
    end

    test "returns false when virtual_host is false", %{original_ex_aws_s3: original} do
      Application.put_env(:ex_aws, :s3, Keyword.put(original || [], :virtual_host, false))

      assert Cache.Config.s3_virtual_host() == false
    end

    test "returns false when virtual_host is not set", %{original_ex_aws_s3: original} do
      Application.put_env(:ex_aws, :s3, Keyword.delete(original || [], :virtual_host))

      assert Cache.Config.s3_virtual_host() == false
    end

    test "returns false when ex_aws s3 config is nil" do
      Application.put_env(:ex_aws, :s3, nil)

      assert Cache.Config.s3_virtual_host() == false
    end
  end
end
