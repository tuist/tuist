defmodule Atlas.TuistFeatureFlags do
  @moduledoc """
  Authorized, audited access to Tuist's persisted feature flag rules.

  Tuist owns flag allowlisting, actor resolution, revision checks, idempotency
  and the atomic rule/change audit. Atlas records request outcomes, not proof
  that a failed remote request had no effect.
  """

  alias Atlas.Audit
  alias Atlas.MCP.Tool
  alias Atlas.TuistServer
  alias Atlas.Users
  alias Atlas.Users.User

  @name_schema %{
    "type" => "object",
    "properties" => %{"name" => %{"type" => "string", "minLength" => 1}},
    "required" => ["name"],
    "additionalProperties" => false
  }
  @update_schema %{
    "type" => "object",
    "properties" => %{
      "name" => @name_schema["properties"]["name"],
      "operation" => %{"type" => "string", "enum" => ~w(enable disable clear)},
      "scope" => %{"type" => "string", "enum" => ~w(global account project percentage all)},
      "account_id" => %{"type" => "integer", "minimum" => 1},
      "project_id" => %{"type" => "integer", "minimum" => 1},
      "percentage" => %{
        "type" => "number",
        "exclusiveMinimum" => 0,
        "exclusiveMaximum" => 100
      },
      "expected_revision" => %{"type" => "string", "minLength" => 1},
      "reason" => %{"type" => "string", "minLength" => 1, "maxLength" => 1000},
      "change_id" => %{"type" => "string", "format" => "uuid"}
    },
    "required" => ~w(name operation scope expected_revision reason change_id),
    "additionalProperties" => false
  }

  @evaluation_schema %{
    "type" => "object",
    "properties" => %{
      "account_id" => %{"type" => "integer", "minimum" => 1, "maximum" => 9_223_372_036_854_775_807},
      "project_id" => %{"type" => "integer", "minimum" => 1, "maximum" => 9_223_372_036_854_775_807}
    },
    "oneOf" => [%{"required" => ["account_id"]}, %{"required" => ["project_id"]}],
    "additionalProperties" => false
  }

  def evaluation_schema, do: @evaluation_schema
  def name_schema, do: @name_schema
  def update_schema, do: @update_schema

  def flag_schema do
    %{
      "type" => "object",
      "properties" => %{
        "name" => %{"type" => "string"},
        "actor_type" => %{"type" => "string", "enum" => ~w(global account project)},
        "description" => %{"type" => "string"},
        "revision" => %{"type" => "string"},
        "gates" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "type" => %{"type" => "string"},
              "target" => %{"type" => ["string", "null"]},
              "enabled" => %{"type" => "boolean"}
            },
            "required" => ~w(type target enabled),
            "additionalProperties" => false
          }
        }
      },
      "required" => ~w(name actor_type description revision gates),
      "additionalProperties" => false
    }
  end

  # Slack tools run as a shared operator, not the requesting human. Preserve
  # that origin even when an in-process caller omitted its audit interface.
  def execution_opts(%{assigns: %{mcp_claims: %{"slack_agent" => _}}}), do: [interface: "slack"]
  def execution_opts(conn), do: [interface: Tool.audit_interface(conn)]

  def allowed_context?(conn), do: validate_interface(execution_opts(conn)) == :ok

  def list(user, args, opts \\ []) do
    result =
      with :ok <- validate_interface(opts),
           :ok <- authorize(user, "feature_flags:read"),
           true <- args == %{} do
        TuistServer.list_feature_flags()
      else
        false -> {:error, "This tool accepts no arguments."}
        error -> error
      end

    record("listed", user, nil, %{}, result, opts)
  end

  def get(user, args, opts \\ []) do
    result =
      with :ok <- validate_interface(opts),
           :ok <- authorize(user, "feature_flags:read"),
           :ok <- validate(@name_schema, args),
           :ok <- validate_name(args["name"]) do
        TuistServer.get_feature_flag(args["name"])
      end

    record("inspected", user, target_name(args), %{}, result, opts)
  end

  def evaluate(user, args, opts \\ []) do
    result =
      with :ok <- validate_interface(opts),
           :ok <- authorize(user, "feature_flags:read"),
           :ok <- validate(@evaluation_schema, args) do
        TuistServer.evaluate_feature_flags(args)
      end

    metadata =
      if is_map(args) do
        args
        |> Map.take(~w(account_id project_id))
        |> Map.filter(fn {_, id} -> is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807 end)
      else
        %{}
      end

    record("evaluated", user, nil, metadata, result, opts)
  end

  def update(user, args, opts \\ []) do
    result =
      with :ok <- validate_interface(opts),
           :ok <- authorize(user, "feature_flags:write"),
           :ok <- validate(@update_schema, args),
           :ok <- validate_name(args["name"]),
           :ok <- validate_update(args) do
        attrs =
          args
          |> Map.delete("name")
          |> Map.put("actor", %{"id" => user.id, "email" => user.email})
          |> Map.put("interface", Keyword.get(opts, :interface, "mcp"))

        TuistServer.update_feature_flag(args["name"], attrs)
      end

    metadata =
      if is_map(args) do
        Map.take(args, ~w(operation scope account_id project_id percentage expected_revision reason change_id))
      else
        %{}
      end

    record("updated", user, target_name(args), metadata, result, opts)
  end

  defp authorize(%User{} = user, scope) do
    if Users.has_scope?(user, scope), do: :ok, else: {:error, "Tuist feature flag tools require the #{scope} scope."}
  end

  defp authorize(_user, _scope), do: {:error, "Tuist feature flag tools require an authenticated user."}

  defp validate(schema, args) when is_map(args) do
    schema
    |> ExJsonSchema.Schema.resolve()
    |> ExJsonSchema.Validator.validate(args)
    |> case do
      :ok -> :ok
      {:error, _errors} -> {:error, "Arguments do not match the feature flag tool schema."}
    end
  end

  defp validate(_schema, _args), do: {:error, "Arguments must be an object."}

  defp validate_name(name) when name not in [".", ".."], do: :ok
  defp validate_name(_name), do: {:error, "Invalid feature flag name."}

  defp validate_update(args) do
    with true <- valid_scope?(args),
         {:ok, _uuid} <- Ecto.UUID.cast(args["change_id"]),
         true <- String.trim(args["reason"]) != "" do
      :ok
    else
      _ ->
        {:error,
         "Invalid scope/operation, scope target, reason or change_id UUID. Percentage allows enable or clear; all allows only clear."}
    end
  end

  defp valid_scope?(args) do
    fields = Map.keys(Map.take(args, ~w(account_id project_id percentage))) |> Enum.sort()

    case {args["scope"], args["operation"]} do
      {"global", _} -> fields == []
      {"account", _} -> fields == ["account_id"]
      {"project", _} -> fields == ["project_id"]
      {"percentage", "enable"} -> fields == ["percentage"]
      {"percentage", "clear"} -> fields == []
      {"all", "clear"} -> fields == []
      _ -> false
    end
  end

  defp validate_interface(opts) do
    if Keyword.get(opts, :interface, "mcp") in ~w(mcp worker api),
      do: :ok,
      else: {:error, "Unsupported feature flag interface."}
  end

  defp target_name(%{"name" => name}) when is_binary(name), do: name
  defp target_name(_args), do: nil

  defp record(action, user, name, metadata, result, opts) do
    metadata = Map.put(metadata, "status", if(match?({:ok, _}, result), do: "ok", else: "error"))

    metadata =
      case result do
        {:ok, %{"revision" => revision}} -> Map.put(metadata, "revision", revision)
        _ -> metadata
      end

    Audit.record(
      "tuist_feature_flag.#{action}",
      %{target_type: "tuist_feature_flag", target_id: name, target_label: name, metadata: metadata},
      actor: user,
      interface: Keyword.get(opts, :interface, "mcp")
    )

    result
  end
end
