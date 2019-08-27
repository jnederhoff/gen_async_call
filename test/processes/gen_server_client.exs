defmodule GenServerClient do
  use GenServer
  use GenAsyncCall.GenServer
  import GenAsyncCall, only: [mfa: 1]
  require Logger

  def test_async_sleep(pid, time, opts \\ []) do
    GenServer.call(pid, {:test_async_sleep, time, opts})
  end

  def test_async_sleep_fn(pid, time, opts \\ []) do
    GenServer.call(pid, {:test_async_sleep_fn, time, opts})
  end

  def test_async_sleep_mfa(pid, time, opts \\ []) do
    GenServer.call(pid, {:test_async_sleep_mfa, time, opts})
  end

  def handle_call({:test_async_sleep, time, opts}, from, state) do
    refs = TestServer.async_sleep(state.server, time, opts)

    state =
      state
      |> push_refs(refs)
      |> put_in([:from], from)

    {:noreply, state}
  end

  def handle_call({:test_async_sleep_fn, time, opts}, from, state) do
    refs = TestServer.async_sleep(state.server, time, opts, fn(reply, state) ->
      GenServer.reply(from, {:fn, reply})

      {:noreply, state}
    end)

    state =
      state
      |> push_refs(refs)

    {:noreply, state}
  end

  def handle_call({:test_async_sleep_mfa, time, opts}, from, state) do
    refs = TestServer.async_sleep(state.server, time, opts, mfa(module: __MODULE__, function: :my_mfa, arguments: [from]))

    state =
      state
      |> push_refs(refs)

    {:noreply, state}
  end

  def my_mfa(reply, state, from) do
    GenServer.reply(from, {:mfa, reply})

    {:noreply, state}
  end

  def handle_async_reply({:ok, reply}, _tag, state) do
    GenServer.reply(state.from, reply)

    {:noreply, %{state | from: nil}}
  end

  def handle_async_reply(reply, tag, state) do
    super(reply, tag, state)
  end

  def start_link(init_args) do
    GenServer.start_link(__MODULE__, init_args)
  end

  def init(server) do
    {:ok, %{server: server, from: nil, refs: %{}}}
  end
end
