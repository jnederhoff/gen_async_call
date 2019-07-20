defmodule GenAsyncCall.GenServer do
  @callback handle_async_reply({:ok, reply :: any} | {:error, reason :: term}, tag :: term, state :: term) ::
  {:noreply, new_state}
  | {:noreply, new_state, timeout | :hibernate | {:continue, term}}
  | {:stop, reason :: term, new_state}
  when new_state: term

  @callback interposer(reply :: any, GenAsyncCall.call_refs, state :: term) :: any

  @callback push_refs(state :: term, GenAsyncCall.call_refs) :: new_state :: term

  @callback pop_refs(state :: term, reference) :: {GenAsyncCall.call_refs | nil, new_state :: term}

  @optional_callbacks handle_async_reply: 3

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      require GenAsyncCall

      @behaviour GenAsyncCall.GenServer

      def handle_async_reply({:ok, reply}, _tag, state) do
        # We do this to trick Dialyzer to not complain about non-local returns. Hat tip GenServer.
        case :erlang.phash2(1, 1) do
          0 ->
            raise "a reply that should have been handled by an await or inline callback was not, or you forget to implement handle_async_reply/3"

          1 ->
            {:stop, {:unhandled_reply, reply}, state}
        end
      end

      def handle_async_reply({:error, error}, tag, state) do
        # We do this to trick Dialyzer to not complain about non-local returns. Hat tip GenServer.
        case :erlang.phash2(1, 1) do
          0 ->
            case error do
              {:nodedown, node} ->
                exit({{:nodedown, node}, {__MODULE__, :handle_async_error, [error, tag, state]}})
              {:down, reason} ->
                exit({reason, {__MODULE__, :handle_async_error, [error, tag, state]}})
              :timeout ->
                exit({:timeout, {__MODULE__, :handle_async_error, [error, tag, state]}})
            end

          1 ->
            {:stop, {:call_errored, error}, state}
        end
      end

      def interposer(reply, {_mref, _tref, fref_or_tag}, state) when is_function(fref_or_tag) do
        fref_or_tag.(reply, state)
      end

      def interposer(reply, {_mref, _tref, fref_or_tag}, state) when GenAsyncCall.is_mod_fun_arg(fref_or_tag) do
        {mod, fname, args} = fref_or_tag
        apply(mod, fname, [reply, state | args])
      end

      def interposer(reply, {mref, _tref, fref_or_tag}, state) do
        case fref_or_tag do
          nil ->
            handle_async_reply(reply, mref, state)
          tag ->
            handle_async_reply(reply, tag, state)
        end
      end

      def push_refs(state, refs) do
        GenAsyncCall.push_refs(refs)

        state
      end

      def pop_refs(state, mref) do
        refs = GenAsyncCall.pop_refs(mref)

        {refs, state}
      end

      defoverridable handle_async_reply: 3, interposer: 3, push_refs: 2, pop_refs: 2

      def handle_info({mref, reply}, state) when is_reference(mref) do
        case pop_refs(state, mref) do
          {nil, state} ->
            # No match, drop message
            {:noreply, state}
          {refs, state} ->
            GenAsyncCall.cancel_timer(refs)
            Process.demonitor(mref, [:flush])

            interposer({:ok, reply}, refs, state)
        end
      end

      def handle_info({:DOWN, mref, _, process, :noconnection}, state) do
        case pop_refs(state, mref) do
          {nil, state} ->
            # No match, drop message
            {:noreply, state}
          {refs, state} ->
            GenAsyncCall.cancel_timer(refs)
            node = GenAsyncCall.get_node(process)

            interposer({:error, {:nodedown, node}}, refs, state)
        end
      end

      def handle_info({:DOWN, mref, _, _, reason}, state) do
        case pop_refs(state, mref) do
          {nil, state} ->
            # No match, drop message
            {:noreply, state}
          {refs, state} ->
            GenAsyncCall.cancel_timer(refs)

            interposer({:error, {:down, reason}}, refs, state)
        end
      end

      def handle_info({:async_call_timeout, mref}, state) do
        case pop_refs(state, mref) do
          {nil, state} ->
            # No match, drop message
            {:noreply, state}
          {refs, state} ->
            Process.demonitor(mref, [:flush])

            interposer({:error, :timeout}, refs, state)
        end
      end

      defoverridable handle_info: 2
    end
  end
end
