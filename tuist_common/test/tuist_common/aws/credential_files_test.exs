defmodule TuistCommon.AWS.CredentialFilesTest do
  # Not async: the ExAws test changes the node's `:ex_aws` application env.
  use ExUnit.Case, async: false

  alias TuistCommon.AWS.CredentialFiles

  @moduletag :tmp_dir

  # Lays out credentials the way kubelet mounts a Secret: each file is a
  # symlink through `..data`, which points at a timestamped directory, and an
  # update swaps `..data` atomically.
  defp mount(dir, access_key_id, secret_access_key) do
    version = Path.join(dir, "..#{System.unique_integer([:positive])}")
    File.mkdir_p!(version)
    File.write!(Path.join(version, "access_key_id"), access_key_id <> "\n")
    File.write!(Path.join(version, "secret_access_key"), secret_access_key <> "\n")

    staging = Path.join(dir, "..data_tmp")
    File.rm(staging)
    File.ln_s!(Path.basename(version), staging)
    File.rename!(staging, Path.join(dir, "..data"))

    for name <- ["access_key_id", "secret_access_key"], not File.exists?(Path.join(dir, name)) do
      File.ln_s!(Path.join("..data", name), Path.join(dir, name))
    end

    dir
  end

  defp profile, do: "test-#{System.unique_integer([:positive])}"

  describe "adapt_auth_config/3" do
    test "reads the mounted key pair and follows an update", %{tmp_dir: dir} do
      mount(dir, "KEY1", "secret1")
      profile = profile()

      assert CredentialFiles.adapt_auth_config(%{credentials_dir: dir}, profile, 30_000) ==
               %{access_key_id: "KEY1", secret_access_key: "secret1"}

      mount(dir, "KEY2", "secret2")

      assert CredentialFiles.adapt_auth_config(%{credentials_dir: dir}, profile, 30_000) ==
               %{access_key_id: "KEY2", secret_access_key: "secret2"}
    end

    test "keeps the last key pair when the files become unreadable", %{tmp_dir: dir} do
      mount(dir, "KEY1", "secret1")
      profile = profile()
      CredentialFiles.adapt_auth_config(%{credentials_dir: dir}, profile, 30_000)

      File.rm!(Path.join(dir, "..data"))

      assert CredentialFiles.adapt_auth_config(%{credentials_dir: dir}, profile, 30_000) ==
               %{access_key_id: "KEY1", secret_access_key: "secret1"}
    end

    test "returns an error when nothing was ever read", %{tmp_dir: dir} do
      assert {:error, {:enoent, "access_key_id"}} =
               CredentialFiles.adapt_auth_config(%{credentials_dir: dir}, profile(), 30_000)
    end

    test "hands delegated profiles to their adapter" do
      defmodule Delegate do
        def adapt_auth_config(auth, profile, expiration),
          do: {:delegated, auth, profile, expiration}
      end

      assert CredentialFiles.adapt_auth_config(%{delegate: Delegate, role_arn: "arn"}, "p", 1) ==
               {:delegated, %{role_arn: "arn"}, "p", 1}
    end
  end

  describe "read/1" do
    test "refuses an empty file", %{tmp_dir: dir} do
      mount(dir, "KEY1", "")
      assert CredentialFiles.read(dir) == {:error, {:empty, "secret_access_key"}}
    end
  end

  describe "ex_aws_config/1" do
    test "raises at boot when a directory is missing its files", %{tmp_dir: dir} do
      assert_raise RuntimeError, ~r/not usable/, fn ->
        CredentialFiles.ex_aws_config(%{"s3" => %{credentials_dir: dir}})
      end
    end
  end

  describe "through ExAws" do
    setup do
      previous =
        Map.new(
          [:awscli_credentials, :awscli_auth_adapter],
          &{&1, Application.fetch_env(:ex_aws, &1)}
        )

      on_exit(fn ->
        for {key, value} <- previous do
          case value do
            {:ok, value} -> Application.put_env(:ex_aws, key, value)
            :error -> Application.delete_env(:ex_aws, key)
          end
        end
      end)
    end

    test "an operation configured with the profile signs with the current key", %{tmp_dir: dir} do
      mount(dir, "KEY1", "secret1")
      profile = profile()

      for {key, value} <- CredentialFiles.ex_aws_config(%{profile => %{credentials_dir: dir}}),
          do: Application.put_env(:ex_aws, key, value)

      overrides = [
        access_key_id: CredentialFiles.credential(profile),
        secret_access_key: CredentialFiles.credential(profile)
      ]

      config = ExAws.Config.new(:s3, overrides)
      assert {config.access_key_id, config.secret_access_key} == {"KEY1", "secret1"}

      mount(dir, "KEY2", "secret2")
      # The refresh ExAws schedules every 30 seconds, run now.
      send(ExAws.Config.AuthCache, {:refresh_awscli_config, profile, 30_000})
      :sys.get_state(ExAws.Config.AuthCache)

      config = ExAws.Config.new(:s3, overrides)
      assert {config.access_key_id, config.secret_access_key} == {"KEY2", "secret2"}
    end
  end
end
