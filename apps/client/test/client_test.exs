defmodule ClientTest do
  use ExUnit.Case
  doctest Client

  @client_port Application.compile_env(:client, :local_port)
  @server_port Application.compile_env(:client, :server_port)

  setup_all do
    {:ok, _} = Client.start_link([])
    on_exit(:stop_client, fn -> Client.stop() end)

    opts = [:binary, active: false, reuseaddr: true]
    {:ok, server_listen} = :gen_tcp.listen(@server_port, opts)
    on_exit(:stop_server, fn -> :gen_tcp.close(server_listen) end)

    %{server_listen: server_listen}
  end

  test "should proxy no auth, ipv4, tcp", %{server_listen: ls} do
    dst = <<127, 0, 0, 1, 4321::16>>
    msg_sent = "ping"
    msg_wanted = "pong"

    Task.start_link(fn ->
      # this is the proxy server
      {:ok, client} = :gen_tcp.accept(ls)

      {:ok, <<5, 1, 0>>} = :gen_tcp.recv(client, 0)
      :ok = :gen_tcp.send(client, <<5, 0>>)

      {:ok, <<5, 1, 0, 1, ^dst::binary>>} = :gen_tcp.recv(client, 0)
      :ok = :gen_tcp.send(client, <<5, 0, 0, 1, 127, 0, 0, 1, @server_port::16>>)

      assert {:ok, "ping"} = :gen_tcp.recv(client, 0)
      :ok = :gen_tcp.send(client, "pong")
    end)

    client = connect_to_exocks()

    Process.sleep(100)
    :ok = :gen_tcp.send(client, dst)

    Process.sleep(100)
    client |> send_recv(send: msg_sent, wanted: {:ok, msg_wanted})
  end

  defp connect_to_exocks() do
    opts = [:binary, active: false, reuseaddr: true]
    {:ok, client} = :gen_tcp.connect(:localhost, @client_port, opts)
    client
  end

  defp send_recv(sock, send: sent, wanted: wanted) do
    :ok = :gen_tcp.send(sock, sent)
    assert wanted == :gen_tcp.recv(sock, 0)
    sock
  end
end
