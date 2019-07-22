defmodule GenAsyncCall.GenStateMachine do
  @callback handle_async_reply({:ok, reply :: any} | {:error, reason :: term}, tag :: term, state :: term, data :: term) :: :gen_statem.event_handler_result(GenStateMachine.state)

  @callback gen_async_interposer(reply :: any, GenAsyncCall.call_refs, state :: term, data :: term) :: any

  @callback push_refs(state :: term, data :: term, GenAsyncCall.call_refs) :: {new_state :: term, new_data ::term}

  @callback pop_refs(state :: term, data :: term, reference) :: {GenAsyncCall.call_refs | nil, new_state :: term, new_data :: term}

  @optional_callbacks handle_async_reply: 4

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      require GenAsyncCall

      @behaviour GenAsyncCall.GenStateMachine

      def handle_async_reply({:ok, reply}, _tag, _state, _data) do
        # We do this to trick Dialyzer to not complain about non-local returns. Hat tip GenServer.
        case :erlang.phash2(1, 1) do
          0 ->
            raise "a reply that should have been handled by an await or inline callback was not, or you forget to implement handle_async_reply/4"

          1 ->
            {:stop, {:unhandled_reply, reply}}
        end
      end

      def handle_async_reply({:error, error}, tag, state, data) do
        # We do this to trick Dialyzer to not complain about non-local returns. Hat tip GenServer.
        case :erlang.phash2(1, 1) do
          0 ->
            case error do
              {:nodedown, node} ->
                exit({{:nodedown, node}, {__MODULE__, :handle_async_reply, [error, tag, state, data]}})
              {:down, reason} ->
                exit({reason, {__MODULE__, :handle_async_reply, [error, tag, state, data]}})
              :timeout ->
                exit({:timeout, {__MODULE__, :handle_async_reply, [error, tag, state, data]}})
            end

          1 ->
            {:stop, {:call_errored, error}}
        end
      end

      def gen_async_interposer(reply, {_mref, _tref, fref_or_tag}, state, data) when is_function(fref_or_tag) do
        fref_or_tag.(reply, state, data)
      end

      def gen_async_interposer(reply, {_mref, _tref, fref_or_tag}, state, data) when GenAsyncCall.is_mod_fun_arg(fref_or_tag) do
        {mod, fname, args} = fref_or_tag
        apply(mod, fname, [reply, state, data | args])
      end

      def gen_async_interposer(reply, {mref, _tref, fref_or_tag}, state, data) do
        case fref_or_tag do
          nil ->
            handle_async_reply(reply, mref, state, data)
          tag ->
            handle_async_reply(reply, tag, state, data)
        end
      end

      def push_refs(state, data, refs) do
        GenAsyncCall.push_refs(refs)

        {state, data}
      end

      def pop_refs(state, data, mref) do
        refs = GenAsyncCall.pop_refs(mref)

        {refs, state, data}
      end

      defoverridable handle_async_reply: 4, gen_async_interposer: 4, push_refs: 3, pop_refs: 3

      def handle_event(:info, {mref, reply}, state, data) when is_reference(mref) do
        case pop_refs(state, data, mref) do
          {nil, _state, _data} ->
            # No match, drop message
            :keep_state_and_data
          {refs, state, data} ->
            GenAsyncCall.cancel_timer(refs)
            Process.demonitor(mref, [:flush])

            gen_async_interposer({:ok, reply}, refs, state, data)
        end
      end

      def handle_event(:info, {:DOWN, mref, _, process, :noconnection}, state, data) do
        case pop_refs(state, data, mref) do
          {nil, _state, _data} ->
            # No match, drop message
            :keep_state_and_data
          {refs, state, data} ->
            GenAsyncCall.cancel_timer(refs)
            node = GenAsyncCall.get_node(process)

            gen_async_interposer({:error, {:nodedown, node}}, refs, state, data)
        end
      end

      def handle_event(:info, {:DOWN, mref, _, _, reason}, state, data) do
        case pop_refs(state, data, mref) do
          {nil, _state, _data} ->
            # No match, drop message
            :keep_state_and_data
          {refs, state, data} ->
            GenAsyncCall.cancel_timer(refs)

            gen_async_interposer({:error, {:down, reason}}, refs, state, data)
        end
      end

      def handle_event(:info, {:async_call_timeout, mref}, state, data) do
        case pop_refs(state, data, mref) do
          {nil, _state, _data} ->
            # No match, drop message
            :keep_state_and_data
          {refs, state, data} ->
            Process.demonitor(mref, [:flush])

            gen_async_interposer({:error, :timeout}, refs, state, data)
        end
      end

      defoverridable handle_event: 4
    end
  end
end
