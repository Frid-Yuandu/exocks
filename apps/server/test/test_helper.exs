ExUnit.start()

defmodule TestHelper do
  import ExUnit.Assertions, only: [assert: 1]

  @server_port Application.compile_env(:server, :local_port)

  def connect_to_exocks do
    opts = [:binary, active: false, reuseaddr: true]
    {:ok, sock} = :gen_tcp.connect(:localhost, @server_port, opts)
    sock
  end

  def send_recv(sock, send: sent, wanted: wanted) do
    :ok = :gen_tcp.send(sock, sent)
    assert wanted == :gen_tcp.recv(sock, 0)
    sock
  end
end
