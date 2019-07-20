defmodule TestServer do
  use GenServer

  @default_timeout 100

  def sync_sleep(pid, time, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    GenServer.call(pid, {:sleep, time, opts}, timeout)
  end

  def async_sleep(pid, time, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    GenAsyncCall.async_call(pid, {:sleep, time, opts}, timeout)
  end

  def async_sleep(pid, time, opts, fref) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    GenAsyncCall.async_call(pid, {:sleep, time, opts}, timeout, fref)
  end

  def handle_call({:sleep, time, opts}, from, state) do
    Process.send_after(self(), {:end_sleep, from}, time)

    if time = Keyword.get(opts, :exit_after, false) do
      Process.sleep(time)
      exit(:normal)
    end

    if time = Keyword.get(opts, :crash_after, false) do
      Process.sleep(time)
      Process.exit(self(), :kill)
    end

    {:noreply, state}
  end

  def handle_info({:end_sleep, from}, state) do
    GenServer.reply(from, :slept)

    {:noreply, state}
  end

  def start_link(init_args) do
    GenServer.start_link(__MODULE__, init_args)
  end

  def init(_init_args) do
    {:ok, %{}}
  end
end
