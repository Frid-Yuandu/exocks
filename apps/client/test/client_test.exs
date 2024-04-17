defmodule ClientTest do
  use ExUnit.Case
  doctest Client

  @server_port Application.compile_env(:server, :local_port)
  @client_port Application.compile_env(:client, :local_port)

  test "success procedure" do
    spawn(&Client.start/0)

    spawn(fn ->
      {:ok, socket} = :gen_tcp.listen(@server_port, [:binary, active: false, reuseaddr: true])
      {:ok, client} = :gen_tcp.accept(socket)

      {:ok, <<0x05, 0x01, 0x00>>} = :gen_tcp.recv(client, 0)
      :ok = :gen_tcp.send(client, <<0x05, 0x00>>)

      {:ok, <<0x05, 0x01, 0x00, 0x01, 183, 2, 172, 42, 443::16>>} =
        :gen_tcp.recv(client, 0)

      :ok = :gen_tcp.send(client, <<0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, @server_port::16>>)

      assert {:ok, "ping"} = :gen_tcp.recv(client, 0)
      :ok = :gen_tcp.send(client, "pong")
      assert {:ok, "hello"} = :gen_tcp.recv(client, 0)
      :ok = :gen_tcp.send(client, "world")

      Process.sleep(500)
      :gen_tcp.close(client)
    end)

    {:ok, local} =
      :gen_tcp.connect(
        {127, 0, 0, 1},
        @client_port,
        [:binary, active: false, reuseaddr: true]
      )

    :gen_tcp.send(local, <<183, 2, 172, 42>>)

    Process.sleep(500)
    :gen_tcp.send(local, "ping")
    assert {:ok, "pong"} = :gen_tcp.recv(local, 0)

    Process.sleep(500)
    :gen_tcp.send(local, "hello")
    assert {:ok, "world"} = :gen_tcp.recv(local, 0)

    Process.sleep(500)
    :gen_tcp.close(local)
  end

  test "negotiate success" do
    spawn(fn ->
      {:ok, client} =
        :gen_tcp.connect(:localhost, @client_port, [:binary, active: false, reuseaddr: true])

      :ok = :gen_tcp.send(client, <<5, 0>>)

      Process.sleep(500)
      :gen_tcp.close(client)
    end)

    {:ok, l_socket} = :gen_tcp.listen(@client_port, [:binary, active: false, reuseaddr: true])
    {:ok, server} = :gen_tcp.accept(l_socket)
    assert Client.negotiate(server) == :ok

    Process.sleep(500)
    :gen_tcp.close(server)
  end

  test "negotiate failed" do
    spawn(fn ->
      {:ok, client} =
        :gen_tcp.connect(:localhost, @client_port, [:binary, active: false, reuseaddr: true])

      :ok = :gen_tcp.send(client, <<5, 1>>)

      Process.sleep(500)
      :ok = :gen_tcp.send(client, <<5, 0xFF>>)

      Process.sleep(500)
      :ok = :gen_tcp.send(client, <<4, 1>>)

      Process.sleep(31 * 1000)
      :ok = :gen_tcp.send(client, <<5, 0>>)

      Process.sleep(500)
      :gen_tcp.close(client)
    end)

    {:ok, l_socket} = :gen_tcp.listen(@client_port, [:binary, active: false, reuseaddr: true])
    {:ok, server} = :gen_tcp.accept(l_socket)
    assert Client.negotiate(server) == :stop
    assert Client.negotiate(server) == :stop
    assert Client.negotiate(server) == :stop
    assert Client.negotiate(server) == {:retry, 3}

    Process.sleep(500)
    :gen_tcp.close(server)
  end
end
