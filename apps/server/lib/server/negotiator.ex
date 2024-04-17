defmodule Server.Negotiator do
  @timeout 5 * 1000
  @socks_ver 0x05

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
          version: 0x05,
          method: atom(),
          rule: atom()
        }
  defstruct version: @socks_ver, method: nil, rule: nil

  @spec new(binary(), atom()) :: t()
  def new(request, rule \\ :all)
      when is_binary(request) and is_atom(rule) do
    with methods when is_list(methods) <- Map.get(rule_set(), rule),
         select_method = select(methods, request) do
      %Server.Negotiator{method: select_method, rule: rule}
    else
      nil ->
        raise ArgumentError,
              "invalid rule: #{rule}, " <>
                "available rules: #{rule_set() |> Map.keys() |> Enum.join(", ")}"
    end
  end

  @spec select([non_neg_integer()], binary()) :: atom()
  def select(methods, request)
      when is_binary(request) do
    for m <- methods,
        m in :binary.bin_to_list(request),
        m in enabled() do
      m
    end
    |> Enum.reverse()
    |> List.first(@method_no_acceptable)
    |> then(&Map.get(methods_map(), &1))
  end

  defp enabled do
    for m <- supported(),
        m != @method_user_pass or
          map_size(@passwords) > 0,
        do: m
  end

  @spec negotiate(Server.Negotiator.t(), port()) :: :ok | :method_unacceptable | {:error, reason}
        when reason: atom() | {:timeout, binary()}
  def negotiate(%Server.Negotiator{method: m}, sock)
      when is_port(sock) and is_atom(m) do
    apply(__MODULE__, m, [sock])
  end

  @spec no_auth(port()) :: :ok | {:error, reason}
        when reason: atom() | {:timeout, binary()}
  def no_auth(sock) do
    :gen_tcp.send(sock, <<@socks_ver, @method_no_auth>>)
  end

  @spec user_pass(port()) :: :ok | {:error, reason}
        when reason: atom() | {:timeout, binary()}
  def user_pass(sock) do
    with :ok <- :gen_tcp.send(sock, <<@socks_ver, @method_user_pass>>),
         {:ok, <<@user_pass_version, rest::binary>>} <- :gen_tcp.recv(sock, 0, @timeout),
         {:ok, {username, password}} <- parse_user_password(rest),
         true <- check_user_password(username, password) do
      :gen_tcp.send(sock, <<@user_pass_version, @auth_success>>)
    else
      {:ok, <<ver, _::binary>>} when ver != @user_pass_version ->
        {:error, :invalid_sub_version}

      {:ok, _} ->
        {:error, :invalid_packet}

      :error ->
        # parse_user_password error
        {:error, :invalid_packet}

      false ->
        :gen_tcp.send(sock, <<@user_pass_version, @auth_failure>>)
        {:error, :no_such_user}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec no_acceptable(port()) :: :method_unacceptable | {:error, reason}
        when reason: atom() | {:timeout, binary()}
  def no_acceptable(sock) do
    :gen_tcp.send(sock, <<@socks_ver, @method_no_acceptable>>)
    :method_unacceptable
  end

  defp parse_user_password(<<ulen, rest::binary>>) do
    <<username::binary-size(ulen), plen, password::binary>> = rest
    if plen == byte_size(password), do: {:ok, {username, password}}, else: :error
  end

  defp check_user_password(username, password) do
    password == Map.get(@passwords, username)
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
