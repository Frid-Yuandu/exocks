defmodule ServerTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  doctest Server

  @timeout 6 * 1000
  @server_port Application.compile_env(:server, :local_port)

  setup do
    pid = Server.start()
    on_exit(:stop_listener, fn -> Server.stop(pid) end)
  end

  test "total proxy procedure" do
    # spawn a process simulating target server
    simulate_dst_server(fn server ->
      assert {:ok, "ping"} = :gen_tcp.recv(server, 0)
      :ok = :gen_tcp.send(server, "pong")
      assert {:ok, "hello"} = :gen_tcp.recv(server, 0)
      :ok = :gen_tcp.send(server, "world")
    end)

    {:ok, s} =
      :gen_tcp.connect(
        {127, 0, 0, 1},
        @server_port,
        [:binary, active: false, reuseaddr: true]
      )

    :ok = :gen_tcp.send(s, <<5, 1, 0>>)
    {:ok, <<5, 0>>} = :gen_tcp.recv(s, 0)

    :ok =
      :gen_tcp.send(
        s,
        <<5, 1, 0x00, 1, 127, 0, 0, 1, 443::16>>
      )

    {:ok, <<5, 0x00, 0x00, 0x01, 127, 0, 0, 1, @server_port::16>>} =
      :gen_tcp.recv(s, 0)

    Process.sleep(500)
    :ok = :gen_tcp.send(s, "ping")
    assert {:ok, "pong"} = :gen_tcp.recv(s, 0)

    Process.sleep(500)
    :ok = :gen_tcp.send(s, "hello")
    assert {:ok, "world"} = :gen_tcp.recv(s, 0)
  end

  # test "negotiate invalid version" do
  #   {:ok, s} =
  #     :gen_tcp.connect(
  #       {127, 0, 0, 1},
  #       @server_port,
  #       [:binary, active: false, reuseaddr: true]
  #     )

  #   assert capture_log(fn ->
  #            :ok = :gen_tcp.send(s, <<4, 1, 0>>)
  #            assert {:ok, <<0x05, 0xFF>>} = :gen_tcp.recv(s, 0)
  #          end) =~ "invalid negotiate version"
  # end

  test "negotiate unacceptable method" do
    {:ok, s} =
      :gen_tcp.connect(
        {127, 0, 0, 1},
        @server_port,
        [:binary, active: false, reuseaddr: true]
      )

    :ok = :gen_tcp.send(s, <<5, 1, 0xFE>>)
    assert {:ok, <<0x05, 0xFF>>} = :gen_tcp.recv(s, 0)
  end

  # test "negotiate receive timeout" do
  #   {:ok, _} =
  #     :gen_tcp.connect(
  #       {127, 0, 0, 1},
  #       @server_port,
  #       [:binary, active: false, reuseaddr: true]
  #     )

  #   assert capture_log(fn ->
  #            Process.sleep(@timeout)
  #          end) =~ "receive timeout"
  # end

  # test "stop listener" do
  #   assert capture_log(fn ->
  #            pid = spawn(Server.Listener, :run, [])
  #            send(pid, :listen)

  #            :gen_tcp.connect(:localhost, @server_port, [
  #              :binary,
  #              active: false,
  #              reuseaddr: true
  #            ])

  #            send(pid, :stop)
  #            Process.sleep(1000)
  #          end) =~ "server stop listenning"
  # end

  @spec simulate_dst_server((port() -> any())) :: any()
  def simulate_dst_server(behaviour) do
    Task.start_link(fn ->
      {:ok, sock} = :gen_tcp.listen(443, [:binary, active: false, reuseaddr: true])
      {:ok, server} = :gen_tcp.accept(sock)

      behaviour.(server)
    end)
  end
end
