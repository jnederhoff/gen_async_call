defmodule BareProcessClientTest do
  use ExUnit.Case

  setup _context do
    {:ok, server_pid} = start_supervised(Supervisor.child_spec(TestServer, restart: :temporary))

    {:ok, server: server_pid}
  end

  describe "callback tests:" do
    test "happy path call and reply", context do
      {mref, _tref, _fref} = TestServer.async_sleep(context.server, 10)

      assert_receive {^mref, :slept}
    end

    test "server already dead, client notified", context do
      server_pid = context.server

      Process.exit(server_pid, :kill)
      {mref, _tref, _fref} = TestServer.async_sleep(server_pid, 10)

      assert_receive {:DOWN, ^mref, _, ^server_pid, :noproc}
    end

    test "server exits ok, client notified", context do
      server_pid = context.server

      {mref, _tref, _fref} = TestServer.async_sleep(server_pid, 10, exit_after: 2)

      assert_receive {:DOWN, ^mref, _, ^server_pid, :normal}
    end

    test "server dies, client notified", context do
      server_pid = context.server

      {mref, _tref, _fref} = TestServer.async_sleep(server_pid, 10, crash_after: 2)

      assert_receive {:DOWN, ^mref, _, ^server_pid, :killed}
    end

    test "call timeout", context do
      {mref, _tref, _fref} = TestServer.async_sleep(context.server, 100, timeout: 10)

      assert_receive {:async_call_timeout, ^mref}
    end
  end

  describe "await tests:" do
    test "happy path call and reply", context do
      refs = TestServer.async_sleep(context.server, 10)

      assert {:ok, :slept} = GenAsyncCall.await(refs)
    end

    test "server already dead, client notified", context do
      Process.exit(context.server, :kill)
      refs = TestServer.async_sleep(context.server, 10)

      assert {:error, {:down, :noproc}} = GenAsyncCall.await(refs)
    end

    test "server exits ok, client notified", context do
      refs = TestServer.async_sleep(context.server, 10, exit_after: 2)

      assert {:error, {:down, :normal}} = GenAsyncCall.await(refs)
    end

    test "server dies, client notified", context do
      refs = TestServer.async_sleep(context.server, 10, crash_after: 2)

      assert {:error, {:down, :killed}} = GenAsyncCall.await(refs)
    end

    test "call timeout", context do
      refs = TestServer.async_sleep(context.server, 100, timeout: 10)

      assert {:error, :timeout} = GenAsyncCall.await(refs)
    end
  end

  describe "await function tests:" do
    test "happy path call and reply", context do
      refs = TestServer.async_sleep(context.server, 10, [], fn result -> {:fn, result} end)

      assert {:fn, {:ok, :slept}} = GenAsyncCall.await(refs)
    end

    test "server dies, client notified", context do
      refs = TestServer.async_sleep(context.server, 10, [crash_after: 2], fn result -> {:fn, result} end)

      assert {:fn, {:error, {:down, :killed}}} = GenAsyncCall.await(refs)
    end

    test "call timeout", context do
      refs = TestServer.async_sleep(context.server, 100, [timeout: 10], fn result -> {:fn, result} end)

      assert {:fn, {:error, :timeout}} = GenAsyncCall.await(refs)
    end
  end

  describe "await mfa tests:" do
    test "happy path call and reply", context do
      refs = TestServer.async_sleep(context.server, 10, [], {TestMFA, :my_func, [:arg2]})

      assert {:my_func, {:ok, :slept}} = GenAsyncCall.await(refs)
    end

    test "server dies, client notified", context do
      refs = TestServer.async_sleep(context.server, 10, [crash_after: 2], {TestMFA, :my_func, [:arg2]})

      assert {:my_func, {:error, {:down, :killed}}} = GenAsyncCall.await(refs)
    end

    test "call timeout", context do
      refs = TestServer.async_sleep(context.server, 100, [timeout: 10], {TestMFA, :my_func, [:arg2]})

      assert {:my_func, {:error, :timeout}} = GenAsyncCall.await(refs)
    end
  end

  describe "await! tests:" do
    test "happy path call and reply", context do
      refs = TestServer.async_sleep(context.server, 10)

      assert :slept = GenAsyncCall.await!(refs)
    end

    test "server already dead, client notified", context do
      Process.exit(context.server, :kill)
      refs = TestServer.async_sleep(context.server, 10)

      assert {:noproc, _} = catch_exit(GenAsyncCall.await!(refs))
    end

    test "server exits ok, client notified", context do
      refs = TestServer.async_sleep(context.server, 10, exit_after: 2)

      assert {:normal, _} = catch_exit(GenAsyncCall.await!(refs))
    end

    test "server dies, client notified", context do
      refs = TestServer.async_sleep(context.server, 10, crash_after: 2)

      assert {:killed, _} = catch_exit(GenAsyncCall.await!(refs))
    end

    test "call timeout", context do
      refs = TestServer.async_sleep(context.server, 100, timeout: 10)

      assert {:timeout, _} = catch_exit(GenAsyncCall.await!(refs))
    end
  end

  describe "await! function tests:" do
    test "happy path call and reply", context do
      refs = TestServer.async_sleep(context.server, 10, [], fn result -> {:fn, result} end)

      assert {:fn, :slept} = GenAsyncCall.await!(refs)
    end

    test "server dies, client notified", context do
      refs = TestServer.async_sleep(context.server, 10, [crash_after: 2], fn result -> {:fn, result} end)

      assert {:killed, _} = catch_exit(GenAsyncCall.await!(refs))
    end

    test "call timeout", context do
      refs = TestServer.async_sleep(context.server, 100, [timeout: 10], fn result -> {:fn, result} end)

      assert {:timeout, _} = catch_exit(GenAsyncCall.await!(refs))
    end
  end

  describe "await! mfa tests:" do
    test "happy path call and reply", context do
      refs = TestServer.async_sleep(context.server, 10, [], {TestMFA, :my_func, [:arg2]})

      assert {:my_func, :slept} = GenAsyncCall.await!(refs)
    end

    test "server dies, client notified", context do
      refs = TestServer.async_sleep(context.server, 10, [crash_after: 2], {TestMFA, :my_func, [:arg2]})

      assert {:killed, _} = catch_exit(GenAsyncCall.await!(refs))
    end

    test "call timeout", context do
      refs = TestServer.async_sleep(context.server, 100, [timeout: 10], {TestMFA, :my_func, [:arg2]})

      assert {:timeout, _} = catch_exit(GenAsyncCall.await!(refs))
    end
  end
end

defmodule TestMFA do
  def my_func(result, :arg2) do
    {:my_func, result}
  end
end
