defmodule LuftServer.Workspaces.Definition do
  @moduledoc """
  Compiler for the deliberately small, local workspace pilot. Definitions are
  data, never executable SQL. Production publication/authorization is not wired.
  """

  def load(path) do
    path = Path.expand(path)
    definition = path |> File.read!() |> Jason.decode!()

    if Map.has_key?(definition, "apps"),
      do: compose!(path, definition),
      else: load_flat!(path, definition)
  end

  defp load_flat!(path, definition) do
    validate!(definition)

    modules =
      Enum.map(definition["ui_modules"], fn ui ->
        source = path |> Path.dirname() |> contained_file!(ui["entry"]) |> File.read!()
        ensure!(byte_size(source) <= 1_000_000, "UI source is too large")
        Map.put(ui, "source", source)
      end)

    Map.put(definition, "ui_modules", modules)
  end

  def fixtures(path) do
    raw = path |> File.read!() |> Jason.decode!()

    if Map.has_key?(raw, "apps") do
      raw["apps"]
      |> Enum.map(&app_path!(path, &1))
      |> Enum.reduce(%{}, fn app_path, merged ->
        app = app_path |> File.read!() |> Jason.decode!()
        rows = read_fixtures!(app_path, app["fixtures"])

        ensure!(
          Enum.all?(Map.keys(rows), &Map.has_key?(app["models"], &1)),
          "Fixtures must belong to their app"
        )

        merge_unique!(merged, rows)
      end)
    else
      read_fixtures!(path, raw["fixtures"])
    end
  end

  defp read_fixtures!(path, relative) do
    rows = path |> Path.dirname() |> contained_file!(relative) |> File.read!() |> Jason.decode!()
    ensure!(is_map(rows), "Expected fixture records")
    rows
  end

  defp compose!(path, workspace) do
    keys!(workspace, ~w(format organization title apps))
    ensure!(is_list(workspace["apps"]) and workspace["apps"] != [], "Expected local apps")

    apps =
      Enum.map(workspace["apps"], fn relative ->
        app_path = app_path!(path, relative)
        app = app_path |> File.read!() |> Jason.decode!()

        keys!(
          app,
          ~w(format id version title dependencies models queries actions ui_modules fixtures)
        )

        ensure!(
          app["format"] == 1 and identifier?(app["id"]) and positive_integer?(app["version"]),
          "Invalid app identity"
        )

        ensure!(text?(app["title"]) and is_map(app["dependencies"]), "Invalid app metadata")
        {app_path, app}
      end)

    versions =
      Enum.reduce(apps, %{}, fn {_, app}, acc ->
        merge_unique!(acc, %{app["id"] => app["version"]})
      end)

    Enum.each(apps, fn {_, app} -> validate_app!(app, versions) end)

    merged =
      Enum.reduce(
        apps,
        %{"models" => %{}, "queries" => %{}, "actions" => %{}, "ui_modules" => []},
        fn {app_path, app}, acc ->
          acc =
            Enum.reduce(~w(models queries actions), acc, fn kind, acc ->
              Map.update!(acc, kind, &merge_unique!(&1, app[kind]))
            end)

          modules =
            Enum.map(app["ui_modules"], fn ui ->
              keys!(ui, ~w(id title group model entry capabilities))
              source = app_path |> Path.dirname() |> contained_file!(ui["entry"]) |> File.read!()
              ensure!(byte_size(source) <= 1_000_000, "UI source is too large")
              Map.put(ui, "source", source)
            end)

          Map.update!(acc, "ui_modules", &(&1 ++ modules))
        end
      )

    definition =
      workspace |> Map.delete("apps") |> Map.merge(merged) |> Map.put("fixtures", "app-owned")

    # Validate authored UI keys before adding the runtime-only bundled sources.
    validate!(
      Map.update!(definition, "ui_modules", &Enum.map(&1, fn ui -> Map.delete(ui, "source") end))
    )

    Map.put(
      definition,
      "apps",
      Map.new(apps, fn {_, app} ->
        {app["id"], Map.take(app, ~w(version title dependencies))}
      end)
    )
  end

  defp validate_app!(app, versions) do
    Enum.each(app["dependencies"], fn {id, version} ->
      ensure!(
        identifier?(id) and id != app["id"] and positive_integer?(version) and
          versions[id] == version,
        "Unavailable app dependency or version mismatch"
      )
    end)

    owned? = fn id -> is_binary(id) and String.starts_with?(id, app["id"] <> ".") end

    available! = fn id ->
      ensure!(model_id?(id), "Invalid app dependency ID")
      owner = id |> String.split(".") |> hd()

      ensure!(
        owner == app["id"] or Map.has_key?(app["dependencies"], owner),
        "Undeclared cross-app dependency"
      )
    end

    Enum.each(~w(models queries actions), fn kind ->
      ensure!(is_map(app[kind]), "Expected app definitions")
      ensure!(Enum.all?(Map.keys(app[kind]), owned?), "Definition must belong to its app")
    end)

    Enum.each(app["models"], fn {_, model} ->
      Enum.each(model["fields"], fn {_, field} ->
        if field["type"] == "reference", do: available!.(field["model"])
      end)
    end)

    Enum.each(~w(queries actions), fn kind ->
      Enum.each(app[kind], fn {_, operation} -> available!.(operation["model"]) end)
    end)

    ensure!(is_list(app["ui_modules"]), "Expected UI modules")

    Enum.each(app["ui_modules"], fn ui ->
      ensure!(owned?.(ui["id"]), "UI must belong to its app")
      available!.(ui["model"])

      Enum.each(~w(queries actions), fn kind ->
        Enum.each(ui["capabilities"][kind], available!)
      end)
    end)
  end

  defp app_path!(workspace, relative) do
    ensure!(
      is_binary(relative) and Path.type(relative) == :relative,
      "Expected relative app path"
    )

    Path.expand(relative, Path.dirname(workspace))
  end

  defp merge_unique!(left, right) do
    ensure!(Map.keys(left) -- Map.keys(right) == Map.keys(left), "Duplicate app or definition ID")
    Map.merge(left, right)
  end

  defp positive_integer?(value), do: is_integer(value) and value > 0

  def validate!(definition) do
    ensure!(is_map(definition), "Expected a workspace object")
    keys!(definition, ~w(format organization title models queries actions ui_modules fixtures))
    ensure!(definition["format"] == 1, "Unsupported workspace format")
    ensure!(identifier?(definition["organization"]), "Invalid organization")
    ensure!(text?(definition["title"]), "Missing workspace title")
    models = definition["models"]
    ensure!(is_map(models) and map_size(models) in 1..20, "Expected 1–20 models")

    Enum.each(models, fn {id, model} ->
      ensure!(model_id?(id), "Invalid model ID")
      keys!(model, ~w(version fields))
      ensure!(is_integer(model["version"]) and model["version"] > 0, "Invalid model version")
      fields = model["fields"]
      ensure!(is_map(fields) and map_size(fields) in 1..40, "Expected 1–40 fields")

      Enum.each(fields, fn {name, field} ->
        ensure!(identifier?(name) and name not in ~w(id revision), "Invalid or reserved field")
        keys!(field, ~w(type required nullable default values model))
        ensure!(field["type"] in ~w(string enum reference), "Unsupported field type")

        if field["type"] == "reference" do
          ensure!(
            model_id?(field["model"]) and Map.has_key?(models, field["model"]),
            "Unknown reference model"
          )
        else
          ensure!(!Map.has_key?(field, "model"), "Only references have target models")
        end

        Enum.each(~w(required nullable), fn key ->
          ensure!(!Map.has_key?(field, key) or is_boolean(field[key]), "Invalid field flag")
        end)

        ensure!(
          !(field["required"] == true and field["nullable"] == true),
          "Conflicting nullability"
        )

        if field["type"] == "enum" do
          values = field["values"]

          ensure!(
            is_list(values) and length(values) in 1..30 and Enum.all?(values, &text?/1) and
              Enum.uniq(values) == values,
            "Invalid enum values"
          )
        else
          ensure!(!Map.has_key?(field, "values"), "Only enums have values")
        end

        if Map.has_key?(field, "default"),
          do: ensure!(valid_value?(field, field["default"]), "Invalid field default")
      end)
    end)

    validate_operations!(definition["queries"], models, ["list", "get"])
    validate_operations!(definition["actions"], models, ["create", "update"])
    ensure!(is_list(definition["ui_modules"]), "Expected UI modules")
    ids = Enum.map(definition["ui_modules"], & &1["id"])
    ensure!(Enum.uniq(ids) == ids, "Duplicate UI module")
    all_ids = ids ++ Enum.flat_map(~w(models queries actions), &Map.keys(definition[&1]))
    ensure!(Enum.uniq(all_ids) == all_ids, "Duplicate definition ID")

    Enum.each(definition["ui_modules"], fn ui ->
      keys!(ui, ~w(id title group model entry capabilities))

      ensure!(
        model_id?(ui["id"]) and text?(ui["title"]) and text?(ui["group"]),
        "Invalid UI module"
      )

      ensure!(Map.has_key?(models, ui["model"]), "Unknown UI model")
      ensure!(text?(ui["entry"]), "Missing UI entry")
      keys!(ui["capabilities"], ~w(queries actions))

      Enum.each(~w(queries actions), fn kind ->
        names = ui["capabilities"][kind]
        ensure!(is_list(names), "Missing module capabilities")
        ensure!(Enum.all?(names, &Map.has_key?(definition[kind], &1)), "Unknown capability")
      end)
    end)

    ensure!(text?(definition["fixtures"]), "Missing fixture file")
    definition
  end

  def contained_file!(directory, relative) do
    ensure!(
      is_binary(relative) and Path.type(relative) == :relative,
      "Expected relative workspace file"
    )

    root = Path.expand(directory)
    path = Path.expand(relative, root)
    ensure!(String.starts_with?(path, root <> "/"), "Workspace file escapes its root")
    # Refuse symlinks in any path component, not only at the leaf.
    relative
    |> Path.split()
    |> Enum.reduce(root, fn part, parent ->
      next = Path.join(parent, part)
      ensure!(File.lstat!(next).type != :symlink, "Workspace files cannot be symlinks")
      next
    end)
  end

  def valid_value?(field, nil), do: field["required"] != true and field["nullable"] != false

  def valid_value?(%{"type" => "reference"}, value),
    do: uuid?(value)

  def valid_value?(field, value) do
    is_binary(value) and String.valid?(value) and byte_size(value) <= 4000 and
      (field["required"] != true or String.trim(value) != "") and
      (field["type"] != "enum" or value in field["values"])
  end

  def uuid?(value),
    do: is_binary(value) and byte_size(value) == 36 and match?({:ok, _}, Ecto.UUID.cast(value))

  def table(id), do: "model_" <> String.slice(hash(id), 0, 24)
  def quote_id(id), do: ~s("#{id}")
  def hash(value), do: Base.encode16(:crypto.hash(:sha256, value), case: :lower)
  def ensure!(true, _message), do: :ok
  def ensure!(_, message), do: raise(ArgumentError, message)

  defp identifier?(value),
    do: is_binary(value) and Regex.match?(~r/\A[a-z][a-z0-9_]{0,47}\z/, value)

  defp model_id?(value),
    do:
      is_binary(value) and
        Regex.match?(~r/\A[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)?\z/, value) and
        byte_size(value) <= 120

  defp text?(value),
    do:
      is_binary(value) and String.valid?(value) and String.trim(value) != "" and
        byte_size(value) <= 4000

  defp keys!(map, allowed) do
    ensure!(is_map(map), "Expected an object")
    ensure!(Map.keys(map) -- allowed == [], "Unknown definition keys")
  end

  defp validate_operations!(operations, models, allowed) do
    ensure!(is_map(operations), "Expected operation definitions")

    Enum.each(operations, fn {id, operation} ->
      keys!(operation, ~w(model operation))
      ensure!(model_id?(id), "Invalid operation name")
      ensure!(Map.has_key?(models, operation["model"]), "Unknown operation model")
      ensure!(operation["operation"] in allowed, "Unsupported operation")
    end)
  end
end
