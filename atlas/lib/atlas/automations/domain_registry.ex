defmodule Atlas.Automations.DomainRegistry do
  @moduledoc "Versioned, explicitly reviewed platform capabilities. Never discover handlers from user input."

  alias Atlas.Automations.Contract

  @manifest_path Path.expand("../../../priv/automation/contracts/v1.json", __DIR__)
  @external_resource @manifest_path
  @manifest @manifest_path |> File.read!() |> JSON.decode!()
  @entries @manifest["operations"]
  @handlers Map.new(@entries, fn entry -> {entry["handler"], String.to_atom(entry["handler"])} end)
  @adapters @entries
            |> Enum.reject(&Map.has_key?(&1, "action"))
            |> Map.new(fn entry -> {entry["handler"], String.to_atom(entry["handler"])} end)

  def entries, do: @entries
  def exclusions, do: @manifest["excluded_tools"]
  def domain_policies, do: @manifest["domain_policies"]

  def types do
    Enum.map(@entries, fn entry ->
      %{
        name: entry["name"],
        reference: reference(entry),
        description: entry["description"],
        domain: entry["domain"],
        effect: entry["effect"],
        version: entry["version"],
        permissions: entry["permissions"],
        execution_mode: entry["execution_mode"],
        requires_approval: entry["requires_approval"],
        input_schema: entry["input_schema"],
        output_schema: entry["output_schema"]
      }
    end)
  end

  def reference(entry), do: entry["name"] <> "@" <> Integer.to_string(entry["version"])

  def fetch(name, version) do
    case Enum.find(@entries, &(&1["name"] == name and &1["version"] == version)) do
      nil -> {:error, "Unsupported domain operation version."}
      entry -> {:ok, entry}
    end
  end

  def fetch(reference) when is_binary(reference) and byte_size(reference) <= 160 do
    case String.split(reference, "@") do
      [name, version] ->
        case Integer.parse(version) do
          {version, ""} when version > 0 -> fetch(name, version)
          _ -> {:error, "Unsupported domain operation version."}
        end

      [name] ->
        @entries
        |> Enum.filter(&(&1["name"] == name))
        |> Enum.max_by(& &1["version"], fn -> nil end)
        |> case do
          nil -> {:error, "Unknown domain operation."}
          entry -> {:ok, entry}
        end

      _ ->
        {:error, "Unknown domain operation."}
    end
  end

  def fetch(_), do: {:error, "Unknown domain operation."}

  def handler(entry), do: Map.fetch!(@handlers, entry["handler"])
  def adapter(entry), do: Map.fetch!(@adapters, entry["handler"])

  def snapshot(entry) do
    %{
      "type" => entry["name"],
      "version" => entry["version"],
      "configuration" => %{},
      "input_schema" => entry["input_schema"],
      "output_schema" => entry["output_schema"]
    }
  end

  def validate_snapshot(entry, behavior) do
    if behavior == snapshot(entry), do: :ok, else: {:error, "A domain operation must use its frozen contract."}
  end

  def validate_entry(entry) do
    with :ok <- Contract.validate_schema(entry["input_schema"]) do
      Contract.validate_schema(entry["output_schema"])
    end
  end
end
