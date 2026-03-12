defmodule Cache.DistributedKV.Logic do
  @moduledoc false

  def compare_source_versions(nil, _left_node, nil, _right_node), do: :eq
  def compare_source_versions(nil, _left_node, _right_time, _right_node), do: :lt
  def compare_source_versions(_left_time, _left_node, nil, _right_node), do: :gt

  def compare_source_versions(left_time, left_node, right_time, right_node) do
    case DateTime.compare(left_time, right_time) do
      :eq -> compare_strings(left_node || "", right_node || "")
      other -> other
    end
  end

  def max_datetime(nil, right), do: right
  def max_datetime(left, nil), do: left
  def max_datetime(left, right), do: if(DateTime.before?(left, right), do: right, else: left)

  def merge_shared_entry(existing, incoming, now) do
    winning_payload? =
      compare_source_versions(
        incoming.source_updated_at,
        incoming.source_node,
        existing.source_updated_at,
        existing.source_node
      ) == :gt

    payload_source_updated_at =
      if winning_payload? do
        incoming.source_updated_at
      else
        existing.source_updated_at
      end

    deleted_at = merge_deleted_at(existing.deleted_at, payload_source_updated_at, winning_payload?)

    %{
      account_handle: incoming.account_handle,
      project_handle: incoming.project_handle,
      cas_id: incoming.cas_id,
      json_payload: if(winning_payload?, do: incoming.json_payload, else: existing.json_payload),
      source_node: if(winning_payload?, do: incoming.source_node, else: existing.source_node),
      source_updated_at: payload_source_updated_at,
      last_accessed_at: max_datetime(existing.last_accessed_at, incoming.last_accessed_at),
      deleted_at: deleted_at,
      updated_at: now
    }
  end

  def merge_deleted_at(nil, _payload_source_updated_at, _winning_payload?), do: nil

  def merge_deleted_at(deleted_at, payload_source_updated_at, true) do
    if DateTime.after?(payload_source_updated_at, deleted_at), do: nil, else: deleted_at
  end

  def merge_deleted_at(deleted_at, _payload_source_updated_at, false), do: deleted_at

  def compare_strings(left, right) do
    cond do
      left > right -> :gt
      left < right -> :lt
      true -> :eq
    end
  end
end
