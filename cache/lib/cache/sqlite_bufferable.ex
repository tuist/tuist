defmodule Cache.SQLiteBufferable do
  @moduledoc false

  @callback buffer_name() :: atom()
  @callback init_state() :: term()
  @callback handle_event(state :: term(), event :: term()) :: term()
  @callback flush_batches(state :: term(), max_batch_size :: non_neg_integer()) ::
              {list({atom(), term()}), term()}
  @callback queue_stats(state :: term()) :: map()
  @callback queue_empty?(state :: term()) :: boolean()
  @callback write_batch(operation :: atom(), entries :: term()) :: term()
end
