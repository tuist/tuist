defmodule Atlas.Engineering.Projects.Webhooks do
  @moduledoc """
  Manages inbound webhooks attached to a project. Tokens are generated once
  on creation: the plaintext is returned to the caller, only the SHA-256
  hash is persisted, and verification hashes the URL-supplied token and
  looks it up by hash.
  """

  import Ecto.Query

  alias Atlas.Engineering.Projects.Project
  alias Atlas.Engineering.Projects.Webhook
  alias Atlas.Repo

  @token_bytes 32
  @token_prefix "awh_"
  @attr_key_map %{
    "name" => :name,
    "source" => :source
  }
  @attr_keys Map.values(@attr_key_map)

  def list_for_project(%Project{id: project_id}), do: list_for_project(project_id)

  def list_for_project(project_id) when is_binary(project_id) do
    Webhook
    |> where([webhook], webhook.project_id == ^project_id)
    |> order_by([webhook], desc: webhook.inserted_at)
    |> Repo.all()
  end

  def create(%Project{} = project, attrs) do
    token = generate_token()
    hash = hash_token(token)

    attrs =
      attrs
      |> normalize_attrs()
      |> Map.put(:project_id, project.id)
      |> Map.put(:token_hash, hash)

    %Webhook{}
    |> Webhook.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, webhook} -> {:ok, {webhook, token}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def delete(%Webhook{} = webhook), do: Repo.delete(webhook)

  def find_by_token(project_id, source, token) when is_binary(project_id) and is_atom(source) and is_binary(token) do
    hash = hash_token(token)
    Repo.get_by(Webhook, token_hash: hash, project_id: project_id, source: source)
  end

  def find_by_token(_project_id, _source, _token), do: nil

  def touch_last_used(%Webhook{} = webhook) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    webhook
    |> Ecto.Changeset.change(last_used_at: now)
    |> Repo.update()
  end

  defp generate_token do
    @token_prefix <>
      (@token_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false))
  end

  defp hash_token(token) do
    :sha256
    |> :crypto.hash(token)
    |> Base.encode16(case: :lower)
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    attrs
    |> Enum.reduce(%{}, &put_known_attr/2)
    |> Map.update(:source, nil, &cast_source/1)
  end

  defp put_known_attr({key, value}, acc) when is_binary(key) do
    case Map.fetch(@attr_key_map, key) do
      {:ok, attr} -> Map.put(acc, attr, value)
      :error -> acc
    end
  end

  defp put_known_attr({key, value}, acc) when key in @attr_keys, do: Map.put(acc, key, value)
  defp put_known_attr(_entry, acc), do: acc

  defp cast_source(value) when is_atom(value), do: value

  defp cast_source(value) when is_binary(value) do
    case Enum.find(Webhook.sources(), &(Atom.to_string(&1) == value)) do
      nil -> value
      source -> source
    end
  end

  defp cast_source(value), do: value
end
