defmodule Atlas.MCP.Serializers.Assets do
  @moduledoc false

  alias Atlas.Assets
  alias Atlas.Assets.Asset
  alias Atlas.Assets.Assignment
  alias Atlas.Assets.Event
  alias Atlas.MCP.Tool

  def asset_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "asset_tag" => %{"type" => ["string", "null"]},
        "serial_number" => %{"type" => ["string", "null"]},
        "manufacturer" => %{"type" => ["string", "null"]},
        "model" => %{"type" => ["string", "null"]},
        "category" => %{"type" => "string"},
        "state" => %{"type" => "string"},
        "ownership" => %{"type" => "string"},
        "ownership_acquired_on" => %{"type" => ["string", "null"], "format" => "date"},
        "location" => %{"type" => "string"},
        "purchased_on" => %{"type" => ["string", "null"], "format" => "date"},
        "placed_in_service_on" => %{"type" => ["string", "null"], "format" => "date"},
        "acquisition_cost" => %{"type" => "string"},
        "acquisition_currency" => %{"type" => "string"},
        "useful_life_months" => %{"type" => "integer"},
        "warranty_end_on" => %{"type" => ["string", "null"], "format" => "date"},
        "assigned_to_id" => %{"type" => ["string", "null"]},
        "assigned_to_label" => %{"type" => ["string", "null"]},
        "data_center_id" => %{"type" => ["string", "null"]},
        "data_center_name" => %{"type" => ["string", "null"]},
        "hardware_url" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "name",
        "category",
        "state",
        "ownership",
        "location",
        "acquisition_cost",
        "acquisition_currency",
        "useful_life_months",
        "hardware_url"
      ],
      "additionalProperties" => false
    }
  end

  def asset(%Asset{} = asset) do
    %{
      id: asset.id,
      name: asset.name,
      asset_tag: asset.asset_tag,
      serial_number: asset.serial_number,
      manufacturer: asset.manufacturer,
      model: asset.model,
      category: asset.category,
      state: asset.state,
      ownership: asset.ownership,
      ownership_acquired_on: iso_date(asset.ownership_acquired_on),
      location: asset.location,
      purchased_on: iso_date(asset.purchased_on),
      placed_in_service_on: iso_date(asset.placed_in_service_on),
      acquisition_cost: Decimal.to_string(asset.acquisition_cost, :normal),
      acquisition_currency: asset.acquisition_currency,
      useful_life_months: asset.useful_life_months,
      warranty_end_on: iso_date(asset.warranty_end_on),
      assigned_to_id: asset.assigned_to_id,
      assigned_to_label: assigned_to_label(asset),
      data_center_id: asset.data_center_id,
      data_center_name: data_center_name(asset),
      hardware_url: Tool.asset_url(asset.id)
    }
  end

  defp data_center_name(%Asset{data_center: %Ecto.Association.NotLoaded{}}), do: nil
  defp data_center_name(%Asset{data_center: nil}), do: nil
  defp data_center_name(%Asset{data_center: %{name: name}}), do: name

  def asset_list_schema do
    %{
      "type" => "object",
      "properties" => %{
        "assets" => %{"type" => "array", "items" => asset_schema()},
        "count" => %{"type" => "integer"},
        "hardware_url" => %{"type" => "string"}
      },
      "required" => ["assets", "count", "hardware_url"],
      "additionalProperties" => false
    }
  end

  def asset_list(assets) do
    %{
      assets: Enum.map(assets, &asset/1),
      count: length(assets),
      hardware_url: Tool.hardware_url()
    }
  end

  def assignment_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "asset_id" => %{"type" => "string"},
        "user_id" => %{"type" => "string"},
        "user_label" => %{"type" => "string"},
        "assigned_on" => %{"type" => "string", "format" => "date"},
        "returned_on" => %{"type" => ["string", "null"], "format" => "date"},
        "notes" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "asset_id", "user_id", "user_label", "assigned_on"],
      "additionalProperties" => false
    }
  end

  def assignment(%Assignment{} = a) do
    %{
      id: a.id,
      asset_id: a.asset_id,
      user_id: a.user_id,
      user_label: a.user_label_snapshot,
      assigned_on: Date.to_iso8601(a.assigned_on),
      returned_on: iso_date(a.returned_on),
      notes: a.notes
    }
  end

  def assignment_list_schema do
    %{
      "type" => "object",
      "properties" => %{
        "assignments" => %{"type" => "array", "items" => assignment_schema()},
        "count" => %{"type" => "integer"}
      },
      "required" => ["assignments", "count"],
      "additionalProperties" => false
    }
  end

  def assignment_list(assignments) do
    %{assignments: Enum.map(assignments, &assignment/1), count: length(assignments)}
  end

  def event_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "asset_id" => %{"type" => "string"},
        "event_type" => %{"type" => "string"},
        "occurred_on" => %{"type" => "string", "format" => "date"},
        "notes" => %{"type" => ["string", "null"]},
        "expenditure" => %{"type" => ["string", "null"]},
        "expenditure_currency" => %{"type" => ["string", "null"]},
        "previous_warranty_end_on" => %{"type" => ["string", "null"], "format" => "date"},
        "new_warranty_end_on" => %{"type" => ["string", "null"], "format" => "date"}
      },
      "required" => ["id", "asset_id", "event_type", "occurred_on"],
      "additionalProperties" => false
    }
  end

  def event(%Event{} = event) do
    %{
      id: event.id,
      asset_id: event.asset_id,
      event_type: event.event_type,
      occurred_on: Date.to_iso8601(event.occurred_on),
      notes: event.notes,
      expenditure: decimal_string(event.expenditure),
      expenditure_currency: event.expenditure_currency,
      previous_warranty_end_on: iso_date(event.previous_warranty_end_on),
      new_warranty_end_on: iso_date(event.new_warranty_end_on)
    }
  end

  def event_list_schema do
    %{
      "type" => "object",
      "properties" => %{
        "events" => %{"type" => "array", "items" => event_schema()},
        "count" => %{"type" => "integer"}
      },
      "required" => ["events", "count"],
      "additionalProperties" => false
    }
  end

  def event_list(events) do
    %{events: Enum.map(events, &event/1), count: length(events)}
  end

  def book_value_schema do
    %{
      "type" => "object",
      "properties" => %{
        "asset_id" => %{"type" => "string"},
        "on" => %{"type" => "string", "format" => "date"},
        "value" => %{"type" => ["string", "null"]},
        "currency" => %{"type" => ["string", "null"]},
        "excluded_reason" => %{"type" => ["string", "null"]}
      },
      "required" => ["asset_id", "on"],
      "additionalProperties" => false
    }
  end

  def book_value(%Asset{} = asset, on: date) do
    case Assets.book_value_at(asset, on: date) do
      {:ok, value, currency} ->
        %{
          asset_id: asset.id,
          on: Date.to_iso8601(date),
          value: Decimal.to_string(value, :normal),
          currency: currency,
          excluded_reason: nil
        }

      {:error, reason} ->
        %{
          asset_id: asset.id,
          on: Date.to_iso8601(date),
          value: nil,
          currency: nil,
          excluded_reason: to_string(reason)
        }
    end
  end

  defp assigned_to_label(%Asset{assigned_to: %Ecto.Association.NotLoaded{}}), do: nil
  defp assigned_to_label(%Asset{assigned_to: nil}), do: nil

  defp assigned_to_label(%Asset{assigned_to: %{name: name, email: email}}) when is_binary(name),
    do: "#{name} <#{email}>"

  defp assigned_to_label(%Asset{assigned_to: %{email: email}}), do: email

  defp iso_date(nil), do: nil
  defp iso_date(%Date{} = d), do: Date.to_iso8601(d)

  defp decimal_string(nil), do: nil
  defp decimal_string(%Decimal{} = d), do: Decimal.to_string(d, :normal)
end
