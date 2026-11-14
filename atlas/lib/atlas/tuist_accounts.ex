defmodule Atlas.TuistAccounts do
  @moduledoc """
  Authorized, audited operator access to Tuist accounts: resolving a handle
  to the Tuist account ID that feature flag gates, runner limits and plans are
  keyed by, reading or changing the account's runner concurrency limits, and
  reading or changing its billing plan as the ops account page does.

  These are rollout controls alongside `Atlas.TuistFeatureFlags`, so they use
  the same `feature_flags:read`/`feature_flags:write` scopes and the same
  execution-context rules: shared-identity Slack sessions are refused and the
  actor and interface come from the authenticated context. Tuist owns the
  revision check, idempotency and the atomic change audit; Atlas records
  request outcomes.
  """

  alias Atlas.Audit
  alias Atlas.TuistFeatureFlags
  alias Atlas.TuistServer
  alias Atlas.Users
  alias Atlas.Users.User

  @account_id %{"type" => "integer", "minimum" => 1, "maximum" => 9_223_372_036_854_775_807}
  # Tuist stores limits as PostgreSQL integers.
  @resource %{"type" => "integer", "minimum" => 1, "maximum" => 2_147_483_647}

  @lookup_schema %{
    "type" => "object",
    "properties" => %{"handle" => %{"type" => "string", "minLength" => 1, "maxLength" => 255}},
    "required" => ["handle"],
    "additionalProperties" => false
  }
  @limits_schema %{
    "type" => "object",
    "properties" => %{"account_id" => @account_id},
    "required" => ["account_id"],
    "additionalProperties" => false
  }
  @update_limits_schema %{
    "type" => "object",
    "properties" => %{
      "account_id" => @account_id,
      "platform" => %{"type" => "string", "enum" => ~w(linux macos)},
      "vcpus" => @resource,
      "memory_gb" => @resource,
      "expected_revision" => %{"type" => "string", "minLength" => 1},
      "reason" => %{"type" => "string", "minLength" => 1, "maxLength" => 1000},
      "change_id" => %{"type" => "string", "format" => "uuid"}
    },
    "required" => ~w(account_id platform vcpus memory_gb expected_revision reason change_id),
    "additionalProperties" => false
  }

  @text %{"type" => "string", "minLength" => 1, "maxLength" => 255}
  @update_plan_schema %{
    "type" => "object",
    "properties" => %{
      "account_id" => @account_id,
      "operation" => %{"type" => "string", "enum" => ~w(upgrade_to_enterprise start_open_source cancel_at_period_end)},
      # Only for upgrade_to_enterprise, when the Stripe customer lacks them.
      "billing_details" => %{
        "type" => "object",
        "properties" => %{
          "name" => @text,
          "email" => %{"type" => "string", "minLength" => 3, "maxLength" => 320},
          "address" => %{
            "type" => "object",
            "properties" => %{
              "line1" => @text,
              "line2" => @text,
              "city" => @text,
              "state" => @text,
              "postal_code" => @text,
              "country" => %{"type" => "string", "pattern" => "^[A-Za-z]{2}$"}
            },
            "required" => ~w(line1 city postal_code country),
            "additionalProperties" => false
          }
        },
        "required" => ~w(name email address),
        "additionalProperties" => false
      },
      "expected_revision" => %{"type" => "string", "minLength" => 1},
      "reason" => %{"type" => "string", "minLength" => 1, "maxLength" => 1000},
      "change_id" => %{"type" => "string", "format" => "uuid"}
    },
    "required" => ~w(account_id operation expected_revision reason change_id),
    "additionalProperties" => false
  }

  def lookup_schema, do: @lookup_schema
  def limits_schema, do: @limits_schema
  def update_limits_schema, do: @update_limits_schema
  # A plan read takes the same single account ID as a limits read.
  def plan_schema, do: @limits_schema
  def update_plan_schema, do: @update_plan_schema

  def account_schema do
    %{
      "type" => "object",
      "properties" => %{
        "account_id" => %{"type" => "integer"},
        "handle" => %{"type" => "string"},
        "type" => %{"type" => "string", "enum" => ~w(organization user)},
        "organization_id" => %{"type" => ["integer", "null"]},
        "user_id" => %{"type" => ["integer", "null"]}
      },
      "required" => ~w(account_id handle type organization_id user_id),
      "additionalProperties" => false
    }
  end

  def limits_output_schema do
    integer = %{"type" => "integer"}

    %{
      "type" => "object",
      "properties" => %{
        "account_id" => integer,
        "account_handle" => %{"type" => "string"},
        "revision" => %{"type" => "string"},
        "limits" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "platform" => %{"type" => "string", "enum" => ~w(linux macos)},
              "vcpus" => integer,
              "memory_gb" => integer,
              "used_vcpus" => integer,
              "used_memory_gb" => integer,
              "default_vcpus" => integer,
              "default_memory_gb" => integer
            },
            "required" => ~w(platform vcpus memory_gb used_vcpus used_memory_gb default_vcpus default_memory_gb),
            "additionalProperties" => false
          }
        }
      },
      "required" => ~w(account_id account_handle revision limits),
      "additionalProperties" => false
    }
  end

  def plan_output_schema do
    string = %{"type" => "string"}
    nullable_string = %{"type" => ["string", "null"]}

    subscription_properties = %{
      "subscription_id" => string,
      "plan" => string,
      "status" => string,
      "cancel_at_period_end" => %{"type" => "boolean"},
      "current_period_start" => nullable_string,
      "current_period_end" => nullable_string,
      "trial_end" => nullable_string,
      "created_at" => string,
      "updated_at" => string
    }

    subscription = %{
      "type" => "object",
      "properties" => subscription_properties,
      "required" => Map.keys(subscription_properties),
      "additionalProperties" => false
    }

    %{
      "type" => "object",
      "properties" => %{
        "account_id" => %{"type" => "integer"},
        "account_handle" => string,
        "stripe_customer_id" => nullable_string,
        "effective_plan" => %{"type" => "string", "enum" => ~w(air pro enterprise open_source)},
        "subscription" => Map.put(subscription, "type", ["object", "null"]),
        "recent_subscriptions" => %{"type" => "array", "items" => subscription},
        "payment_failed" => %{"type" => "boolean"},
        "cache_access_blocked" => %{"type" => "boolean"},
        "revision" => string
      },
      "required" => ~w(account_id account_handle stripe_customer_id effective_plan subscription recent_subscriptions
                       payment_failed cache_access_blocked revision),
      "additionalProperties" => false
    }
  end

  def lookup(user, args, opts \\ []) do
    result =
      with :ok <- validate_interface(opts),
           :ok <- authorize(user, "feature_flags:read"),
           :ok <- validate(@lookup_schema, args),
           :ok <- validate_handle(args["handle"]) do
        TuistServer.lookup_account(args["handle"])
      end

    metadata = if is_map(args) and is_binary(args["handle"]), do: %{"handle" => args["handle"]}, else: %{}

    metadata =
      case result do
        {:ok, %{"account_id" => id}} -> Map.put(metadata, "account_id", id)
        _ -> metadata
      end

    record("tuist_account.looked_up", user, nil, metadata, result, opts)
  end

  def get_limits(user, args, opts \\ []) do
    result =
      with :ok <- validate_interface(opts),
           :ok <- authorize(user, "feature_flags:read"),
           :ok <- validate(@limits_schema, args) do
        TuistServer.get_runner_concurrency_limits(args["account_id"])
      end

    record("tuist_runner_concurrency.inspected", user, account_id(args), %{}, result, opts)
  end

  def update_limits(user, args, opts \\ []) do
    result =
      with :ok <- validate_interface(opts),
           :ok <- authorize(user, "feature_flags:write"),
           :ok <- validate(@update_limits_schema, args),
           :ok <- validate_update(args),
           :ok <- TuistFeatureFlags.approve_write(user, "update-runner-concurrency-limits", args, opts) do
        attrs =
          args
          |> Map.delete("account_id")
          |> Map.put("actor", %{"id" => user.id, "email" => user.email})
          |> Map.put("interface", Keyword.get(opts, :interface, "mcp"))

        TuistServer.update_runner_concurrency_limits(args["account_id"], attrs)
      end

    metadata =
      if is_map(args),
        do: Map.take(args, ~w(platform vcpus memory_gb expected_revision reason change_id)),
        else: %{}

    record("tuist_runner_concurrency.updated", user, account_id(args), metadata, result, opts)
  end

  def get_plan(user, args, opts \\ []) do
    result =
      with :ok <- validate_interface(opts),
           :ok <- authorize(user, "feature_flags:read"),
           :ok <- validate(@limits_schema, args) do
        TuistServer.get_account_plan(args["account_id"])
      end

    record("tuist_account_plan.inspected", user, account_id(args), %{}, result, opts)
  end

  def update_plan(user, args, opts \\ []) do
    result =
      with :ok <- validate_interface(opts),
           :ok <- authorize(user, "feature_flags:write"),
           :ok <- validate(@update_plan_schema, args),
           :ok <- validate_update(args),
           :ok <- TuistFeatureFlags.approve_write(user, "update-account-plan", args, opts) do
        attrs =
          args
          |> Map.delete("account_id")
          |> Map.put("actor", %{"id" => user.id, "email" => user.email})
          |> Map.put("interface", Keyword.get(opts, :interface, "mcp"))

        TuistServer.update_account_plan(args["account_id"], attrs)
      end

    # Billing details stay out of the audit metadata; mcp.tool_called keeps the arguments.
    metadata =
      if is_map(args),
        do: Map.take(args, ~w(operation expected_revision reason change_id)),
        else: %{}

    metadata =
      case result do
        {:ok, %{"effective_plan" => plan}} -> Map.put(metadata, "effective_plan", plan)
        _ -> metadata
      end

    record("tuist_account_plan.updated", user, account_id(args), metadata, result, opts)
  end

  defp authorize(%User{} = user, scope) do
    if Users.has_scope?(user, scope), do: :ok, else: {:error, "Tuist account tools require the #{scope} scope."}
  end

  defp authorize(_user, _scope), do: {:error, "Tuist account tools require an authenticated user."}

  defp validate(schema, args) when is_map(args) do
    schema
    |> ExJsonSchema.Schema.resolve()
    |> ExJsonSchema.Validator.validate(args)
    |> case do
      :ok -> :ok
      {:error, _errors} -> {:error, "Arguments do not match the Tuist account tool schema."}
    end
  end

  defp validate(_schema, _args), do: {:error, "Arguments must be an object."}

  defp validate_handle(handle) do
    if String.trim(handle) == "", do: {:error, "Invalid Tuist account handle."}, else: :ok
  end

  defp validate_update(args) do
    with {:ok, _uuid} <- Ecto.UUID.cast(args["change_id"]),
         true <- String.trim(args["reason"]) != "" do
      :ok
    else
      _ -> {:error, "Invalid reason or change_id UUID."}
    end
  end

  # The feature flag tools' rule: shared-identity Slack and unknown interfaces are refused.
  defp validate_interface(opts) do
    if Keyword.get(opts, :interface, "mcp") in ~w(mcp worker api),
      do: :ok,
      else: {:error, "Unsupported Tuist account tool interface."}
  end

  defp account_id(%{"account_id" => id}) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807, do: id
  defp account_id(_args), do: nil

  defp record(action, user, account_id, metadata, result, opts) do
    metadata = Map.put(metadata, "status", if(match?({:ok, _}, result), do: "ok", else: "error"))

    metadata =
      case result do
        {:ok, %{"revision" => revision}} -> Map.put(metadata, "revision", revision)
        _ -> metadata
      end

    target_id = if account_id, do: Integer.to_string(account_id)

    Audit.record(
      action,
      %{target_type: "tuist_account", target_id: target_id, target_label: target_id, metadata: metadata},
      actor: user,
      interface: Keyword.get(opts, :interface, "mcp")
    )

    result
  end
end
