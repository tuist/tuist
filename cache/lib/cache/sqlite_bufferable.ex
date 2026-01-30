defmodule Cache.SQLiteBufferable do
  @moduledoc false

  @callback buffer_name() :: atom()
  @callback flush_entries(table :: atom(), max_batch_size :: non_neg_integer()) ::
              list({atom(), term()})
  @callback queue_stats(table :: atom()) :: %{total: non_neg_integer()}
  @callback queue_empty?(table :: atom()) :: boolean()
  @callback write_batch(operation :: atom(), entries :: term()) :: term()
end
