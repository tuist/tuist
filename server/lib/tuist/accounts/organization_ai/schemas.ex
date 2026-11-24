defmodule Tuist.Accounts.OrganizationAI.Schemas do
  @moduledoc """
  The organization AI configuration as the API (`TuistWeb.API.OrganizationAIController`)
  and the MCP tools return it, so both surfaces share one shape. The MCP tools read
  the schema through `Tuist.MCP.Tool.json_schema/1`. Settings call connections
  providers, and a configured model's upstream ID is `upstream_model_id` so that
  `model_id` always refers to a configured model. Credentials are never included.
  """
  alias OpenApiSpex.Schema
  alias Tuist.Accounts.OrganizationAI

  def configuration do
    %Schema{
      title: "OrganizationAIConfiguration",
      type: :object,
      properties: %{
        providers: %Schema{type: :array, items: provider()},
        models: %Schema{type: :array, items: model()},
        default_model_id: %Schema{
          type: :integer,
          nullable: true,
          description:
            "The configured model tasks without a route use, or null. Without a default, only routed tasks send requests."
        },
        task_routes: %Schema{type: :array, items: route()},
        tasks: %Schema{
          type: :array,
          description: "Every routable task and the model its requests use now.",
          items: %Schema{
            title: "OrganizationAITask",
            type: :object,
            properties: %{
              task: task_property(),
              category: %Schema{type: :string, enum: categories(), description: "The product area the task belongs to."},
              model_id: %Schema{
                type: :integer,
                nullable: true,
                description: "The configured model the task uses, or null when it sends no requests."
              },
              source: %Schema{
                type: :string,
                enum: ["route", "default", "none"],
                description:
                  "`route`: the task's own route. `default`: no route, so the default model. `none`: neither, so the task sends no requests."
              }
            },
            required: [:task, :category, :model_id, :source]
          }
        }
      },
      required: [:providers, :models, :default_model_id, :task_routes, :tasks]
    }
  end

  defp provider do
    %Schema{
      title: "OrganizationAIProvider",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        kind: %Schema{
          type: :string,
          enum: ["api_key", "claude_linked_billing"],
          description:
            "`api_key`: an OpenAI-compatible endpoint with a stored key. `claude_linked_billing`: a linked Claude organization, linked from the dashboard."
        },
        name: %Schema{type: :string},
        base_url: %Schema{type: :string, nullable: true, description: "Null for a linked Claude organization."},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :kind, :name, :base_url, :updated_at]
    }
  end

  defp model do
    %Schema{
      title: "OrganizationAIModel",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        provider_id: %Schema{type: :integer},
        upstream_model_id: %Schema{type: :string, description: "The model ID requests send to the provider."},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :provider_id, :upstream_model_id, :updated_at]
    }
  end

  defp route do
    %Schema{
      title: "OrganizationAITaskRoute",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        task: task_property(),
        model_id: %Schema{type: :integer, description: "The configured model the task uses instead of the default."},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :task, :model_id, :updated_at]
    }
  end

  def task_property,
    do: %Schema{
      type: :string,
      enum: Enum.map(OrganizationAI.tasks(), fn {task, _} -> to_string(task) end),
      description:
        "`pulse_grouping`: decide whether Pulse observations belong together. `pulse_explanation`: name and explain Pulse symptoms."
    }

  defp categories, do: OrganizationAI.tasks() |> Enum.map(fn {_, category} -> to_string(category) end) |> Enum.uniq()

  def serialize(configuration) do
    %{
      providers:
        Enum.map(configuration.connections, fn connection ->
          connection
          |> Map.take([:id, :kind, :name, :base_url])
          |> Map.put(:updated_at, DateTime.to_iso8601(connection.updated_at))
        end),
      models:
        Enum.map(configuration.models, fn model ->
          %{
            id: model.id,
            name: model.name,
            provider_id: model.connection_id,
            upstream_model_id: model.model_id,
            updated_at: DateTime.to_iso8601(model.updated_at)
          }
        end),
      default_model_id: configuration.default_model_id,
      task_routes:
        Enum.map(configuration.routes, fn route ->
          %{
            id: route.id,
            task: to_string(route.task),
            model_id: route.model_id,
            updated_at: DateTime.to_iso8601(route.updated_at)
          }
        end),
      tasks:
        Enum.map(OrganizationAI.tasks(), fn {task, category} ->
          route = Enum.find(configuration.routes, &(&1.task == task))

          {model_id, source} =
            cond do
              route -> {route.model_id, "route"}
              configuration.default_model_id -> {configuration.default_model_id, "default"}
              true -> {nil, "none"}
            end

          %{task: to_string(task), category: to_string(category), model_id: model_id, source: source}
        end)
    }
  end

  @doc "Maps API and MCP field names onto `OrganizationAI`'s settings attributes."
  def attrs(params, id \\ nil) do
    params
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> rename("provider_id", "connection_id")
    |> rename("upstream_model_id", "model_id")
    |> then(&if(id, do: Map.put(&1, "_id", id), else: &1))
  end

  defp rename(params, from, to) do
    case Map.pop(params, from) do
      {nil, params} -> params
      {value, params} -> Map.put(params, to, value)
    end
  end
end
