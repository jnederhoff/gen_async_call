defmodule GenAsyncCall do
  @moduledoc """
  Documentation for GenAsyncCall.
  """

  @typedoc "The GenServer name"
  @type name :: atom | {:global, any} | {:via, module, any}

  @typedoc """
  The server reference.
  This is either a plain PID or a value representing a registered name.
  """
  @type server :: pid | name | {atom, node}

  @typedoc """
  A message indicating that a monitored process has exited.
  """
  @type down_message :: {:DOWN, reference, :process, pid | {atom, node}, reason :: any}

  @typedoc """
  A message indicating that an async call has timed out.
  """
  @type async_call_timeout :: {:async_call_timeout, reference}

  @typedoc """
  A message indicating that an async call has replied successfully
  """
  @type async_call_reply :: {reference, reply :: any}

  @typedoc """
  A tuple containing references to the monitor and timeout associated with a call.
  """
  @type call_refs ::
          {monitor_ref :: reference, timer_ref :: reference | :infinity,
           function_ref :: function | mfa | nil}

  @typedoc """
  A tuple containing a Module atom, a function atom, and a list of arguments
  """
  @type mod_fun_arg :: {module, function :: atom, arguments :: list}

  defguard is_mod_fun_arg(fref_or_tag) when is_tuple(fref_or_tag) and tuple_size(fref_or_tag) == 3 and is_atom(elem(fref_or_tag, 0)) and is_atom(elem(fref_or_tag, 1)) and is_list(elem(fref_or_tag,2))

  defguard is_timeout(timeout) when (is_integer(timeout) and timeout >= 0) or timeout == :infinity

  @doc """
  Makes an asynchronous call to the `server` and continues execution. The
  reply will be `await`ed or handled in `c:handle_async_reply` per the
  programmer's choice.
  `server` can be any of the values described in the "Name registration"
  section of the GenServer documentation.
  ## Timeouts
  `timeout` is an integer greater than zero which specifies how many
  milliseconds to wait for a reply, or the atom `:infinity` to wait
  indefinitely. The default value is `5000`. If no reply is received within
  the specified time, an `async_call_timeout` argument is given to
  `c:handle_async_reply`. In the default implementation, any late replies
  will be discarded. If overriden, the caller must in this case be prepared
  for this and discard any such garbage `async_call_reply` messages.
  """
  @spec async_call(server, request :: term) :: call_refs
  def async_call(server, request) do
    async_call(server, request, 5000, nil)
  end

  @spec async_call(server, request :: term, timeout | term) :: call_refs
  def async_call(server, request, timeout) when is_timeout(timeout) do
    async_call(server, request, timeout, nil)
  end

  def async_call(server, request, fref_or_tag) do
    async_call(server, request, 5000, fref_or_tag)
  end

  @spec async_call(server, request :: term, timeout, function | mod_fun_arg | term) :: call_refs
  def async_call(server, request, timeout, fref_or_tag)
      when is_timeout(timeout) do
    case GenServer.whereis(server) do
      nil ->
        exit({:noproc, {__MODULE__, :async_call, [server, request, timeout, fref_or_tag]}})

      pid when pid == self() ->
        exit({:calling_self, {__MODULE__, :async_call, [server, request, timeout, fref_or_tag]}})

      pid ->
        mref = Process.monitor(pid)

        tref =
          case timeout do
            :infinity ->
              :infinity

            timeout ->
              Process.send_after(self(), {:async_call_timeout, mref}, timeout)
          end

        Process.send(pid, {:"$gen_call", {self(), mref}, request}, [])

        {mref, tref, fref_or_tag}
    end
  end

  @spec await(call_refs) :: any
  def await({mref, tref, fref_or_tag}) when is_function(fref_or_tag) do
    # strip fref_or_tag since this function is specially handling it
    do_await({mref, tref, nil})
    |> fref_or_tag.()
  end

  def await({mref, tref, fref_or_tag}) when is_mod_fun_arg(fref_or_tag) do
    {mod, fname, args} = fref_or_tag

    # strip fref_or_tag since this function is specially handling it
    apply(mod, fname, [do_await({mref, tref, nil}) | args])
  end

  def await(refs) do
    do_await(refs)
  end

  @spec do_await(call_refs) ::
          {:ok, reply :: any} | {:ok, reply :: any, tag :: term} | {:error, :timeout | {:down, reason :: any} | {:nodedown, node}}
  defp do_await({mref, _tref, fref_or_tag} = refs) do
    receive do
      {^mref, reply} ->
        cancel_timer(refs)
        Process.demonitor(mref, [:flush])
        case fref_or_tag do
          nil ->
            {:ok, reply}
          tag ->
            {:ok, reply, tag}
        end

      {:DOWN, ^mref, _, process, :noconnection} ->
        cancel_timer(refs)
        node = get_node(process)
        {:error, {:nodedown, node}}

      {:DOWN, ^mref, _, _, reason} ->
        cancel_timer(refs)
        {:error, {:down, reason}}

      {:async_call_timeout, ^mref} ->
        Process.demonitor(mref, [:flush])
        {:error, :timeout}
    end
  end

  def await!({mref, tref, fref_or_tag}) when is_function(fref_or_tag) do
    # strip fref_or_tag since this function is specially handling it
    do_await!({mref, tref, nil})
    |> fref_or_tag.()
  end

  def await!({mref, tref, fref_or_tag}) when is_mod_fun_arg(fref_or_tag) do
    {mod, fname, args} = fref_or_tag

    # strip fref_or_tag since this function is specially handling it
    apply(mod, fname, [do_await!({mref, tref, nil}) | args])
  end

  def await!(refs) do
    do_await!(refs)
  end

  @spec do_await!(call_refs) :: reply :: any
  defp do_await!(refs) do
    case do_await(refs) do
      {:ok, value} ->
        value
      {:ok, value, tag} ->
        {value, tag}
      {:error, {:nodedown, node}} ->
        exit({{:nodedown, node}, {__MODULE__, :do_await!, [refs]}})
      {:error, {:down, reason}} ->
        exit({reason, {__MODULE__, :do_await!, [refs]}})
      {:error, :timeout} ->
        exit({:timeout, {__MODULE__, :do_await!, [refs]}})
    end
  end

  @spec format_error(error_tuple :: tuple) :: String.t()
  def format_error({:nodedown, node}) do
    "node down: #{inspect(node)}"
  end

  def format_error({:down, reason}) do
    "process down: #{inspect(reason)}"
  end

  def format_error(:timeout) do
    "async call timed out"
  end

  @spec get_node(pid | {any, node}) :: node
  def get_node(process) do
    # Copied from Erlang's :gen module since it is not exported
    case process do
      {_s, n} when is_atom(n) ->
        n

      _ when is_pid(process) ->
        node(process)
    end
  end

  @spec cancel_timer(call_refs) :: :ok
  def cancel_timer({mref, tref, _fref_or_tag}) do
    case tref do
      :infinity ->
        :ok

      _ ->
        Process.cancel_timer(tref, async: false, info: false)

        # Flush a timeout message that may have been
        # sent before the timer was cancelled
        receive do
          {:async_call_timeout, ^mref} ->
            :ok
        after
          0 ->
            :ok
        end
    end
  end

  def push_refs({mref, _, _} = refs) do
    refs_map =
      Process.get(:async_call_refs, %{})
      |> Map.put(mref, refs)

    Process.put(:async_call_refs, refs_map)
  end

  def pop_refs(mref) do
    {refs, refs_map} =
      Process.get(:async_call_refs, %{})
      |> Map.pop(mref)

    Process.put(:async_call_refs, refs_map)

    refs
  end
end
