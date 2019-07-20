defmodule GenAsyncCallTest do
  use ExUnit.Case
  doctest GenAsyncCall, import: true

  setup _context do
    {:ok, server_pid} = start_supervised(TestServer)

    {:ok, server: server_pid}
  end

  test "standard genserver call works", context do
    # Make sure we did not break the standard .call() path
    assert TestServer.sync_sleep(context.server, 10) == :slept
  end
end
