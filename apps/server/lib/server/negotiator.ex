defmodule Server.Negotiator do
  alias Server.Negotiator
  @timeout 5 * 1000
  @socks_version 0x05

  # methods list
  @method_no_auth 0x00
  @method_user_pass 0x02
  @method_no_acceptable 0xFF

  # user pass
  @user_pass_version 0x01
  @auth_success 0x00
  @auth_failure 0x01
  @passwords Application.compile_env(:server, :passwords, %{})

  @type t() :: %__MODULE__{
          method: atom(),
          rule: atom()
        }
  defstruct method: nil, rule: :all

  @spec parse(Negotiator.t(), binary()) :: Negotiator.t()
  def parse(%Negotiator{rule: r} = n, req)
      when is_binary(req) do
    methods = Map.fetch!(rule_set(), r)
    selected = select(methods, req)
    %Negotiator{n | method: selected}
  end

  @spec select([non_neg_integer()], binary()) :: atom()
  defp select(methods, request)
       when is_binary(request) do
    for m <- methods,
        m in :binary.bin_to_list(request),
        m in enabled() do
      m
    end
    # reverse in order to choose methods safer than no_auth.
    |> Enum.reverse()
    |> List.first(@method_no_acceptable)
    |> then(&Map.get(methods_map(), &1))
  end

  defp enabled do
    for m <- supported(),
        # this guard filter the user pass method if no passwords set
        m != @method_user_pass or
          map_size(@passwords) > 0,
        do: m
  end

  @spec negotiate(Negotiator.t(), port()) ::
          :ok | :method_unacceptable | {:error, reason}
        when reason: atom() | {:timeout, binary()}
  def negotiate(%Negotiator{method: m}, sock)
      when is_port(sock) do
    apply(__MODULE__, m, [sock])
  end

  @spec no_auth(port()) :: :ok | {:error, reason}
        when reason: atom() | {:timeout, binary()}
  def no_auth(sock) do
    :gen_tcp.send(sock, <<@socks_version, @method_no_auth>>)
  end

  @spec user_pass(port()) :: :ok | {:error, reason}
        when reason: atom() | {:timeout, binary()}
  def user_pass(sock) do
    with :ok <- :gen_tcp.send(sock, <<@socks_version, @method_user_pass>>),
         {:ok, <<@user_pass_version, rest::binary>>} <- :gen_tcp.recv(sock, 0, @timeout),
         {username, password} <- parse_user_password(rest),
         {true, _} <- check_user_password(username, password) do
      :gen_tcp.send(sock, <<@user_pass_version, @auth_success>>)
    else
      {:ok, <<ver, _::binary>>} when ver != @user_pass_version ->
        {:error, :invalid_sub_version}

      {false, username} ->
        :gen_tcp.send(sock, <<@user_pass_version, @auth_failure>>)
        {:error, :no_such_user, username}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec no_acceptable(port()) :: :method_unacceptable | {:error, reason}
        when reason: atom() | {:timeout, binary()}
  def no_acceptable(sock) do
    :gen_tcp.send(sock, <<@socks_version, @method_no_acceptable>>)
    :method_unacceptable
  end

  defp parse_user_password(<<
         user_len,
         user::binary-size(user_len),
         pass_len,
         pass::binary-size(pass_len)
       >>) do
    {user, pass}
  end

  defp check_user_password(username, password) do
    {
      password == Map.get(@passwords, username),
      username
    }
  end

  defp supported do
    [@method_no_auth, @method_user_pass]
  end

  defp rule_set do
    %{
      all: [@method_no_auth, @method_user_pass],
      user_pass: [@method_user_pass]
    }
  end

  defp methods_map do
    %{
      @method_no_auth => :no_auth,
      @method_user_pass => :user_pass,
      @method_no_acceptable => :no_acceptable
    }
  end
end
