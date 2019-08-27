defmodule GenStateMachineClient do
  use GenStateMachine
  use GenAsyncCall.GenStateMachine
  import GenAsyncCall, only: [mfa: 1]
  require Logger

  def test_async_sleep(pid, time, opts \\ []) do
    GenStateMachine.call(pid, {:test_async_sleep, time, opts})
  end

  def test_async_sleep_fn(pid, time, opts \\ []) do
    GenStateMachine.call(pid, {:test_async_sleep_fn, time, opts})
  end

  def test_async_sleep_mfa(pid, time, opts \\ []) do
    GenStateMachine.call(pid, {:test_async_sleep_mfa, time, opts})
  end

  def handle_event({:call, from}, {:test_async_sleep, time, opts}, state, data) do
    refs = TestServer.async_sleep(data.server, time, opts)

    {_state, data} = push_refs(state, data, refs)
    data = put_in(data, [:from], from)

    {:keep_state, data}
  end

  def handle_event({:call, from}, {:test_async_sleep_fn, time, opts}, state, data) do
    refs = TestServer.async_sleep(data.server, time, opts, fn(reply, _state, _data) ->
      GenStateMachine.reply(from, {:fn, reply})

      :keep_state_and_data
    end)

    {_state, data} = push_refs(state, data, refs)

    {:keep_state, data}
  end

  def handle_event({:call, from}, {:test_async_sleep_mfa, time, opts}, state, data) do
    refs = TestServer.async_sleep(data.server, time, opts, mfa(module: __MODULE__, function: :my_mfa, arguments: [from]))

    {_state, data} = push_refs(state, data, refs)

    {:keep_state, data}
  end

  def handle_event(event_type, event_content, state, data) do
    super(event_type, event_content, state, data)
  end

  def my_mfa(reply, _state, _data, from) do
    GenStateMachine.reply(from, {:mfa, reply})

    :keep_state_and_data
  end

  def handle_async_reply({:ok, reply}, _tag, _state, data) do
    GenStateMachine.reply(data.from, reply)

    {:keep_state, %{data | from: nil}}
  end

  def handle_async_reply(reply, tag, state, data) do
    super(reply, tag, state, data)
  end

  def start_link(init_args) do
    GenStateMachine.start_link(__MODULE__, init_args)
  end

  def init(server) do
    {:ok, :ready, %{server: server, from: nil}}
  end
end
