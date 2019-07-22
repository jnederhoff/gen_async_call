defmodule GenStateMachineClientTest do
  use ExUnit.Case

  setup _context do
    {:ok, server_pid} = start_supervised(Supervisor.child_spec(TestServer, restart: :temporary))
    {:ok, client_pid} = start_supervised(Supervisor.child_spec({GenStateMachineClient, server_pid}, restart: :temporary))

    {:ok, server: server_pid, client: client_pid}
  end

  describe "callback tests:" do
    test "happy path call and reply", context do
      assert :slept = GenStateMachineClient.test_async_sleep(context.client, 10)
    end

    test "server already dead, client notified", context do
      Process.exit(context.server, :kill)
      assert {{:noproc, _}, _} = catch_exit(GenStateMachineClient.test_async_sleep(context.client, 10))
    end

    test "server exits ok, client notified", context do
      assert {{:normal, _}, _} = catch_exit(GenStateMachineClient.test_async_sleep(context.client, 10, exit_after: 2))
    end

    test "server dies, client notified", context do
      assert {{:killed, _}, _} = catch_exit(GenStateMachineClient.test_async_sleep(context.client, 10, crash_after: 2))
    end

    test "call timeout", context do
      assert {{:timeout, _}, _} = catch_exit(GenStateMachineClient.test_async_sleep(context.client, 100, timeout: 10))
    end
  end

  describe "callback function tests:" do
    test "happy path call and reply", context do
      assert {:fn, {:ok, :slept}} = GenStateMachineClient.test_async_sleep_fn(context.client, 10)
    end

    test "server already dead, client notified", context do
      Process.exit(context.server, :kill)
      assert {:fn, {:error, {:down, :noproc}}} = GenStateMachineClient.test_async_sleep_fn(context.client, 10)
    end

    test "server exits ok, client notified", context do
      assert {:fn, {:error, {:down, :normal}}} = GenStateMachineClient.test_async_sleep_fn(context.client, 10, exit_after: 2)
    end

    test "server dies, client notified", context do
      assert {:fn, {:error, {:down, :killed}}} = GenStateMachineClient.test_async_sleep_fn(context.client, 10, crash_after: 2)
    end

    test "call timeout", context do
      assert {:fn, {:error, :timeout}} = GenStateMachineClient.test_async_sleep_fn(context.client, 100, timeout: 10)
    end
  end

  describe "callback mfa tests:" do
    test "happy path call and reply", context do
      assert {:mfa, {:ok, :slept}} = GenStateMachineClient.test_async_sleep_mfa(context.client, 10)
    end

    test "server already dead, client notified", context do
      Process.exit(context.server, :kill)
      assert {:mfa, {:error, {:down, :noproc}}} = GenStateMachineClient.test_async_sleep_mfa(context.client, 10)
    end

    test "server exits ok, client notified", context do
      assert {:mfa, {:error, {:down, :normal}}} = GenStateMachineClient.test_async_sleep_mfa(context.client, 10, exit_after: 2)
    end

    test "server dies, client notified", context do
      assert {:mfa, {:error, {:down, :killed}}} = GenStateMachineClient.test_async_sleep_mfa(context.client, 10, crash_after: 2)
    end

    test "call timeout", context do
      assert {:mfa, {:error, :timeout}} = GenStateMachineClient.test_async_sleep_mfa(context.client, 100, timeout: 10)
    end
  end
end
