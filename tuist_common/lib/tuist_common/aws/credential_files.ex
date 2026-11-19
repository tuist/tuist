defmodule TuistCommon.AWS.CredentialFiles do
  @moduledoc """
  S3 credentials read from files at runtime, so a key can be replaced without
  restarting the process.

  A directory holds two files, `access_key_id` and `secret_access_key`, such as
  a Kubernetes Secret mounted as a volume: kubelet replaces a mounted Secret's
  files in place (about a minute after the Secret changes), unlike environment
  variables, which a running process never sees change.

  ExAws resolves credentials on every `ExAws.Config.new/2` through its
  `AuthCache`, which calls the configured `awscli_auth_adapter` with the
  profile's entry in `awscli_credentials` and refreshes it every 30 seconds. ExAws allows a single adapter per node, so this one serves
  every profile:

    * `%{credentials_dir: dir}` reads the files in `dir`.
    * `%{delegate: adapter}` hands the profile to another adapter, such as
      `ExAws.STS.AuthCache.AssumeRoleWebIdentityAdapter` for IRSA, so both can
      run in one node.

  An operation keeps the credentials it started with, so it finishes with the
  old key while new operations use the new one. Whoever rotates the key must
  keep the old one valid until both those operations and any presigned URL it
  signed have expired.

  A failed read keeps serving the last credentials read for that profile,
  logging a warning, so a briefly unreadable volume does not take storage down.
  `validate!/1` checks the files at boot, so a missing mount fails the
  deployment instead of the first request.
  """

  @behaviour ExAws.Config.AuthCache.AuthConfigAdapter

  require Logger

  @refresh_seconds 30
  @access_key_id_file "access_key_id"
  @secret_access_key_file "secret_access_key"
  @read_attempts 3

  @doc """
  The value of `access_key_id` and `secret_access_key` in an ExAws config that
  resolves them through `profile`.
  """
  def credential(profile) when is_binary(profile), do: [{:awscli, profile, @refresh_seconds}]

  @doc """
  The top-level `:ex_aws` config for `profiles`, a map of profile name to its
  entry (`%{credentials_dir: dir}` or `%{delegate: adapter}`). Every
  `credentials_dir` is validated first.
  """
  def ex_aws_config(profiles) when is_map(profiles) and map_size(profiles) > 0 do
    for {_profile, %{credentials_dir: dir}} <- profiles, do: validate!(dir)

    [awscli_credentials: profiles, awscli_auth_adapter: __MODULE__]
  end

  @doc """
  Raises unless `dir` holds a non-empty `access_key_id` and `secret_access_key`.
  """
  def validate!(dir) do
    case read(dir) do
      {:ok, _credentials} ->
        :ok

      {:error, reason} ->
        raise "S3 credentials directory #{inspect(dir)} is not usable: #{inspect(reason)}"
    end
  end

  @doc """
  Reads the key pair in `dir`. The ID is read again after the secret, and a
  mismatch retried, so a read that straddles kubelet replacing the files never
  pairs one key's ID with another key's secret.
  """
  def read(dir, attempts \\ @read_attempts)

  def read(_dir, 0), do: {:error, :changed_while_reading}

  def read(dir, attempts) when is_binary(dir) do
    with {:ok, access_key_id} <- read_file(dir, @access_key_id_file),
         {:ok, secret_access_key} <- read_file(dir, @secret_access_key_file),
         {:ok, ^access_key_id} <- read_file(dir, @access_key_id_file) do
      {:ok, %{access_key_id: access_key_id, secret_access_key: secret_access_key}}
    else
      {:ok, _changed} -> read(dir, attempts - 1)
      {:error, reason} -> {:error, reason}
    end
  end

  def read(dir, _attempts), do: {:error, {:invalid_directory, dir}}

  @impl true
  def adapt_auth_config(%{credentials_dir: dir}, profile, _expiration) do
    case read(dir) do
      {:ok, credentials} ->
        remember(profile, credentials)
        credentials

      {:error, reason} ->
        case :persistent_term.get({__MODULE__, profile}, nil) do
          nil ->
            {:error, reason}

          credentials ->
            Logger.warning(
              "Keeping the previous S3 credentials of #{profile}: #{inspect(reason)}"
            )

            credentials
        end
    end
  end

  def adapt_auth_config(%{delegate: adapter} = auth, profile, expiration) do
    adapter.adapt_auth_config(Map.delete(auth, :delegate), profile, expiration)
  end

  def adapt_auth_config(auth, _profile, _expiration), do: auth

  defp read_file(dir, name) do
    case File.read(Path.join(dir, name)) do
      {:ok, content} ->
        case String.trim(content) do
          "" -> {:error, {:empty, name}}
          value -> {:ok, value}
        end

      {:error, reason} ->
        {:error, {reason, name}}
    end
  end

  # Replacing a persistent term makes every process scan for the old value, so
  # it is only written when the key changed, not on every refresh.
  defp remember(profile, credentials) do
    key = {__MODULE__, profile}
    if :persistent_term.get(key, nil) != credentials, do: :persistent_term.put(key, credentials)
  end
end
