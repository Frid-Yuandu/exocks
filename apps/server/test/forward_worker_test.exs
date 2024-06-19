defmodule ForwardWorkerTest do
  use ExUnit.Case
  alias Server.ForwardWorker
  doctest Server

  defmacrop close(sock_1, sock_2) do
    quote do
      on_exit(fn ->
        :gen_tcp.close(unquote(sock_1))
        :gen_tcp.close(unquote(sock_2))
      end)
    end
  end

  setup_all do
    {:ok, ls} = :gen_tcp.listen(6716, opts())
    %{listen_sock: ls}
  end

  setup %{listen_sock: ls} do
    {:ok, fw} = ForwardWorker.start_link()
    %{forward_worker: fw, listen_sock: ls}
  end

  @dst_port 4321

  test "should bind successfully", %{forward_worker: fw, listen_sock: ls} do
    Task.start(fn ->
      # this is the server
      {:ok, ls} = :gen_tcp.listen(@dst_port, opts())
      {:ok, proxy} = :gen_tcp.accept(ls)
      :gen_tcp.close(proxy)
    end)

    Task.start(fn ->
      # this is the client
      {:ok, proxy} = :gen_tcp.connect(:localhost, 6716, opts(active: true))
      :gen_tcp.close(proxy)
    end)

    {:ok, client} = :gen_tcp.accept(ls)
    {:ok, server} = :gen_tcp.connect(:localhost, @dst_port, opts())

    close(client, server)

    assert %{client: client, destination: server} ==
             ForwardWorker.bind(fw, client: client, destination: server)
  end

  test "should bind failed", %{forward_worker: fw, listen_sock: _} do
    assert_raise FunctionClauseError,
                 fn -> ForwardWorker.bind(fw, client: nil, destination: nil) end
  end

  test "should forward from server successfully", %{forward_worker: fw, listen_sock: ls} do
    Task.start(fn ->
      # this is the server
      {:ok, ls} = :gen_tcp.listen(@dst_port, opts())
      {:ok, proxy} = :gen_tcp.accept(ls)
      assert :ok = :gen_tcp.send(proxy, "ping")
      :gen_tcp.close(proxy)
    end)

    Task.start(fn ->
      # this is the client
      {:ok, proxy} = :gen_tcp.connect(:localhost, 6716, opts(active: true))
      assert {:ok, "ping"} = :gen_tcp.recv(proxy, 0)
      :gen_tcp.close(proxy)
    end)

    {:ok, client} = :gen_tcp.accept(ls)
    {:ok, server} = :gen_tcp.connect(:localhost, @dst_port, opts(active: true))

    close(client, server)

    _ = ForwardWorker.bind(fw, client: client, destination: server)
  end

  test "should forward from client failed", %{forward_worker: fw, listen_sock: ls} do
    Task.start(fn ->
      # this is the server
      {:ok, ls} = :gen_tcp.listen(@dst_port, opts())
      {:ok, proxy} = :gen_tcp.accept(ls)
      assert {:error, :timeout} == :gen_tcp.recv(proxy, 0)
      :gen_tcp.close(proxy)
    end)

    Task.start(fn ->
      # this is the client
      {:ok, proxy} = :gen_tcp.connect(:localhost, 6716, opts(active: true))
      assert :ok = :gen_tcp.send(proxy, "should not forward")
      :gen_tcp.close(proxy)
    end)

    {:ok, client} = :gen_tcp.accept(ls)
    {:ok, server} = :gen_tcp.connect(:localhost, @dst_port, opts(active: true))

    close(client, server)

    _ = ForwardWorker.bind(fw, client: client, destination: server)
  end

  defp opts(), do: opts([])
  defp opts(options), do: [:binary, active: false, reuseaddr: true] ++ options
end
