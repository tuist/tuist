defmodule Atlas.MCP.Serializers.TimeOff do
  alias Atlas.MCP.Tool

  def location(location), do: Map.take(location, [:id, :name, :country_code, :subdivision_code, :synced_years])

  def holiday(holiday) do
    holiday
    |> Map.take([:id, :location_id, :name, :source])
    |> Map.put(:date, Date.to_iso8601(holiday.date))
  end

  def booking(booking) do
    booking
    |> Map.take([:id, :user_id, :location_id, :status, :reviewed_by_id])
    |> Map.put(:reviewed_at, booking.reviewed_at && DateTime.to_iso8601(booking.reviewed_at))
    |> Map.put(:starts_on, Date.to_iso8601(booking.starts_on))
    |> Map.put(:ends_on, Date.to_iso8601(booking.ends_on))
  end

  def location_schema do
    object(%{
      "id" => string(),
      "name" => string(),
      "country_code" => string(),
      "subdivision_code" => Tool.nullable(string()),
      "synced_years" => %{"type" => "array", "items" => %{"type" => "integer"}}
    })
  end

  def holiday_schema do
    object(%{"id" => string(), "location_id" => string(), "name" => string(), "date" => string(), "source" => string()})
  end

  def booking_schema do
    object(%{
      "id" => string(),
      "user_id" => string(),
      "location_id" => string(),
      "starts_on" => string(),
      "ends_on" => string(),
      "status" => string(),
      "reviewed_by_id" => Tool.nullable(string()),
      "reviewed_at" => Tool.nullable(string())
    })
  end

  def summary(booking) do
    booking
    |> Map.update!(:starts_on, &Date.to_iso8601/1)
    |> Map.update!(:ends_on, &Date.to_iso8601/1)
  end

  def summary_schema do
    booking_schema()
    |> Map.fetch!("properties")
    |> Map.merge(%{
      "name" => string(),
      "location" => string(),
      "working_days" => %{"type" => "integer"},
      "missing_years" => %{"type" => "array", "items" => %{"type" => "integer"}}
    })
    |> object()
  end

  def page(items, meta),
    do: %{items: items, page: meta.current_page, total_pages: meta.total_pages, total_count: meta.total_count}

  def page_schema(item_schema) do
    object(%{
      "items" => %{"type" => "array", "items" => item_schema},
      "page" => %{"type" => "integer"},
      "total_pages" => %{"type" => "integer"},
      "total_count" => %{"type" => "integer"}
    })
  end

  def response_schema(key, schema), do: object(%{key => schema})

  def object(properties),
    do: %{
      "type" => "object",
      "properties" => properties,
      "required" => Map.keys(properties),
      "additionalProperties" => false
    }

  def string, do: %{"type" => "string"}

  def error({:error, %Ecto.Changeset{} = changeset}), do: {:error, Tool.format_changeset_errors(changeset)}
  def error({:error, reason}), do: {:error, "Time off operation failed: #{reason}"}
end
