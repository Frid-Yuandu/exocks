defmodule ClientTest do
  use ExUnit.Case
  doctest Client

  test "total proxy procedure" do
    spawn(fn ->
      Client.start()
    end)

    spawn(fn ->
      {:ok, socket} = :gen_tcp.listen(6716, [:binary, active: false, reuseaddr: true])
      {:ok, client} = :gen_tcp.accept(socket)

      {:ok, <<0x05, 0x01, 0x00>>} = :gen_tcp.recv(client, 0)
      :ok = :gen_tcp.send(client, <<0x05, 0x00>>)

      {:ok, <<0x05, 0x01, 0x00, 0x01, 183, 2, 172, 42, 443::16>>} =
        :gen_tcp.recv(client, 0)

      :ok = :gen_tcp.send(client, <<0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 6716::16>>)

      assert {:ok, "ping"} = :gen_tcp.recv(client, 0)
      :ok = :gen_tcp.send(client, "pong")
      assert {:ok, "hello"} = :gen_tcp.recv(client, 0)
      :ok = :gen_tcp.send(client, "world")
    end)

    {:ok, local} =
      :gen_tcp.connect(
        {127, 0, 0, 1},
        8899,
        [:binary, active: false, reuseaddr: true]
      )

    :gen_tcp.send(local, <<183, 2, 172, 42>>)

    :gen_tcp.send(local, "ping")
    assert {:ok, "pong"} = :gen_tcp.recv(local, 0)

    :gen_tcp.send(local, "hello")
    assert {:ok, "world"} = :gen_tcp.recv(local, 0)
  end
end
