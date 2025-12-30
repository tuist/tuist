defmodule Mix.Tasks.Secrets.Edit do
  @moduledoc ~S"""
  This task is used to edit the secrets file.
  When no environment is given, it defaults to dev.

  The convention for the naming and location of keys and secret files is:

  priv/
    secrets/
      dev.key
      dev.yml.enc

  EDITOR="zed --wait" mix secrets.edit --env dev
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.Mix

  def run(args) do
    {parsed, _} = OptionParser.parse!(args, strict: [env: :string])
    env = parsed |> Keyword.get(:env, "dev") |> String.to_atom()
    key_file = Path.join(File.cwd!(), "priv/secrets/#{Atom.to_string(env)}.key")

    encrypted_secrets_file = Path.join(File.cwd!(), "priv/secrets/#{Atom.to_string(env)}.yml.enc")

    if not File.exists?(key_file) do
      raise "Key file not found at #{key_file}"
    end

    case EncryptedSecrets.edit(File.read!(key_file), encrypted_secrets_file) do
      :ok -> nil
      {:error, err} -> raise err
    end
  end
end
