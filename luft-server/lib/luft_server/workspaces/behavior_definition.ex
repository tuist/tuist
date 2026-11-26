defmodule LuftServer.Workspaces.BehaviorDefinition do
  @moduledoc "Closed, bounded contracts for the local behavior foundation."

  alias LuftServer.Workspaces.Definition, as: D

  # Shared by agent discovery and tool parameters. Relational checks and UTF-8
  # byte budgets still belong to validate!/1, not to the model's JSON parser.
  def authoring_schema do
    text = %{"type" => "string", "minLength" => 1, "maxLength" => 100}
    names = %{"type" => "array", "items" => text, "maxItems" => 20, "uniqueItems" => true}

    input_field = %{
      "type" => "object",
      "properties" => %{
        "type" => %{"enum" => ["string", "integer", ["string", "null"]]},
        "enum" => %{"type" => "array"},
        "minimum" => %{"type" => "integer"},
        "maximum" => %{"type" => "integer"},
        "maxLength" => %{"type" => "integer", "minimum" => 0},
        "minLength" => %{"type" => "integer", "minimum" => 0}
      },
      "required" => ["type"],
      "additionalProperties" => false
    }

    field = %{
      "type" => "object",
      "properties" => %{
        "type" => %{"enum" => ~w(string enum reference)},
        "required" => %{"type" => "boolean"},
        "nullable" => %{"type" => "boolean"},
        "default" => %{"type" => ["string", "null"]},
        "values" => Map.put(names, "minItems", 1),
        "model" => text
      },
      "required" => ["type"],
      "additionalProperties" => false
    }

    resource = %{
      "type" => "object",
      "properties" => %{
        "title" => text,
        "version" => %{"type" => "integer", "minimum" => 1},
        "fields" => %{"type" => "object", "additionalProperties" => field, "maxProperties" => 20},
        "projection" => names,
        "search" => names,
        "filters" => names,
        "sort" => names,
        "exports" => %{"type" => "object", "additionalProperties" => names}
      },
      "required" => ~w(title version fields projection search filters sort exports),
      "additionalProperties" => false
    }

    method = %{
      "type" => "object",
      "properties" => %{
        "label" => text,
        "operation" => %{"enum" => ~w(create close update delete)},
        "resource" => text,
        "source" => Map.put(text, "maxLength", 32_768),
        "input" => %{
          "type" => "object",
          "properties" => %{
            "type" => %{"const" => "object"},
            "properties" => %{
              "type" => "object",
              "additionalProperties" => input_field,
              "maxProperties" => 20
            },
            "required" => names,
            "additionalProperties" => %{"const" => false}
          },
          "required" => ~w(type properties required additionalProperties),
          "additionalProperties" => false
        }
      },
      "required" => ~w(label operation resource source input),
      "additionalProperties" => false
    }

    %{
      "type" => "object",
      "properties" => %{
        "format" => %{"const" => 1},
        "title" => Map.put(text, "maxLength", 200),
        "resources" => %{
          "type" => "object",
          "additionalProperties" => resource,
          "minProperties" => 1,
          "maxProperties" => 10
        },
        "methods" => %{
          "type" => "object",
          "additionalProperties" => method,
          "minProperties" => 1,
          "maxProperties" => 20
        }
      },
      "required" => ~w(format title resources methods),
      "additionalProperties" => false
    }
  end

  def changes(before, after_definition), do: changes(before || %{}, after_definition, "")

  defp changes(before, after_definition, path) when is_map(before) and is_map(after_definition) do
    before
    |> Map.keys()
    |> Kernel.++(Map.keys(after_definition))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn key ->
      pointer = path <> "/" <> (key |> String.replace("~", "~0") |> String.replace("/", "~1"))

      cond do
        not Map.has_key?(before, key) ->
          [change(pointer, "added", nil, after_definition[key])]

        not Map.has_key?(after_definition, key) ->
          [change(pointer, "removed", before[key], nil)]

        true ->
          changes(before[key], after_definition[key], pointer)
      end
    end)
  end

  defp changes(value, value, _path), do: []
  defp changes(before, after_value, path), do: [change(path, "changed", before, after_value)]

  defp change(path, kind, before, after_value),
    do: %{"path" => path, "kind" => kind, "before" => before, "after" => after_value}

  def validate!(definition) do
    keys!(definition, ~w(format title resources methods))
    D.ensure!(definition["format"] == 1, "Unsupported behavior format")
    text!(definition["title"], 200)
    resources = definition["resources"]
    methods = definition["methods"]
    D.ensure!(is_map(resources) and map_size(resources) in 1..10, "Invalid resources")
    D.ensure!(is_map(methods) and map_size(methods) in 1..20, "Invalid methods")

    Enum.each(resources, fn {id, resource} ->
      id!(id)
      keys!(resource, ~w(title version fields projection search filters sort exports))
      text!(resource["title"], 100)

      D.ensure!(
        is_integer(resource["version"]) and resource["version"] > 0,
        "Invalid schema version"
      )

      fields = resource["fields"]
      D.ensure!(is_map(fields) and map_size(fields) in 1..20, "Invalid fields")

      Enum.each(fields, fn {name, field} ->
        D.ensure!(
          Regex.match?(~r/\A[a-z][a-z_]{0,39}\z/, name) and name not in ~w(id revision deleted),
          "Invalid field"
        )

        keys!(field, ~w(type required nullable default values model))
        D.ensure!(field["type"] in ~w(string enum reference), "Invalid field type")

        for flag <- ~w(required nullable), Map.has_key?(field, flag) do
          D.ensure!(is_boolean(field[flag]), "Invalid field flag")
        end

        if field["type"] == "reference",
          do: D.ensure!(Map.has_key?(resources, field["model"]), "Unknown reference")

        if field["type"] == "enum",
          do:
            D.ensure!(
              is_list(field["values"]) and length(field["values"]) in 1..20 and
                Enum.all?(field["values"], &(is_binary(&1) and byte_size(&1) <= 100)),
              "Invalid enum"
            )

        if Map.has_key?(field, "default"),
          do: D.ensure!(D.valid_value?(field, field["default"]), "Invalid default")
      end)

      for key <- ~w(projection search filters sort) do
        names = resource[key]

        D.ensure!(
          is_list(names) and Enum.uniq(names) == names and
            Enum.all?(names, &Map.has_key?(fields, &1)),
          "Invalid projection"
        )

        if key != "projection",
          do: D.ensure!(names -- resource["projection"] == [], "Query field outside projection")
      end

      D.ensure!(is_map(resource["exports"]), "Invalid exports")

      Enum.each(resource["exports"], fn {audience, projection} ->
        D.ensure!(
          is_binary(audience) and Regex.match?(~r/\A[a-z][a-z_]{0,39}\z/, audience),
          "Invalid audience"
        )

        D.ensure!(
          is_list(projection) and projection -- resource["projection"] == [],
          "Invalid export projection"
        )
      end)
    end)

    Enum.each(methods, fn {id, method} ->
      id!(id)
      keys!(method, ~w(label operation resource input source))
      text!(method["label"], 100)
      text!(method["source"], 32_768)
      D.ensure!(method["operation"] in ~w(create close update delete), "Invalid operation")

      D.ensure!(
        Map.has_key?(resources, method["resource"]) and owner(id) == owner(method["resource"]),
        "Foreign write capability"
      )

      validate_schema!(method["input"])
    end)

    D.ensure!(byte_size(Jason.encode!(definition)) <= 131_072, "Definition exceeds budget")
    definition
  end

  def validate_input(schema, input) do
    if bounded?(input) and
         ExJsonSchema.Validator.valid?(ExJsonSchema.Schema.resolve(schema), input),
       do: :ok,
       else: {:error, :invalid_request}
  end

  def compatible?(nil, _), do: true

  def compatible?(old, new) do
    Enum.all?(old["resources"], fn {id, before} ->
      after_schema = new["resources"][id]

      is_map(after_schema) and
        Enum.all?(before["fields"], fn {field, value} ->
          after_schema["fields"][field] == value
        end) and
        Enum.all?(Map.drop(after_schema["fields"], Map.keys(before["fields"])), fn {_, field} ->
          D.valid_value?(field, nil)
        end) and
        Map.take(before, ~w(projection search filters sort exports)) ==
          Map.take(after_schema, ~w(projection search filters sort exports)) and
        (before == after_schema or after_schema["version"] == before["version"] + 1)
    end) and Enum.all?(old["methods"], fn {id, method} -> new["methods"][id] == method end)
  end

  def owner(id), do: id |> String.split(".") |> hd()
  def table(id), do: D.quote_id("resource_" <> String.slice(D.hash(id), 0, 24))
  def hash(definition), do: definition |> canonical() |> Jason.encode!() |> D.hash()

  def canonical(value) when is_map(value),
    do: value |> Enum.sort() |> Enum.map(fn {k, v} -> [k, canonical(v)] end)

  def canonical(value) when is_list(value), do: Enum.map(value, &canonical/1)
  def canonical(value), do: value

  def bounded?(value, depth \\ 0)
  def bounded?(_, depth) when depth > 16, do: false

  def bounded?(value, depth) when is_map(value),
    do:
      map_size(value) <= 40 and
        Enum.all?(value, fn {k, v} ->
          is_binary(k) and byte_size(k) <= 128 and bounded?(v, depth + 1)
        end)

  def bounded?(value, depth) when is_list(value),
    do: length(value) <= 100 and Enum.all?(value, &bounded?(&1, depth + 1))

  def bounded?(value, _) when is_binary(value), do: byte_size(value) <= 4096

  def bounded?(value, _),
    do:
      is_nil(value) or is_boolean(value) or
        (is_integer(value) and abs(value) <= 9_007_199_254_740_991)

  defp validate_schema!(schema) do
    keys!(schema, ~w(type properties required additionalProperties))

    D.ensure!(
      schema["type"] == "object" and schema["additionalProperties"] == false,
      "Closed object input required"
    )

    D.ensure!(
      is_map(schema["properties"]) and map_size(schema["properties"]) <= 20 and
        is_list(schema["required"]),
      "Invalid input schema"
    )

    D.ensure!(
      schema["required"] -- Map.keys(schema["properties"]) == [],
      "Unknown required input"
    )

    Enum.each(schema["properties"], fn {_, field} ->
      keys!(field, ~w(type enum minimum maximum maxLength minLength))

      D.ensure!(
        field["type"] in ["string", "integer", ["string", "null"]],
        "Unsupported input type"
      )
    end)

    ExJsonSchema.Schema.resolve(schema)
  end

  defp keys!(map, keys),
    do: D.ensure!(is_map(map) and Map.keys(map) -- keys == [], "Unknown contract keys")

  defp id!(id),
    do:
      D.ensure!(
        is_binary(id) and Regex.match?(~r/\A[a-z][a-z_]{0,39}\.[a-z][a-z_]{0,39}\z/, id),
        "Invalid contract ID"
      )

  defp text!(value, limit),
    do:
      D.ensure!(
        is_binary(value) and String.valid?(value) and byte_size(value) in 1..limit,
        "Invalid contract text"
      )
end
