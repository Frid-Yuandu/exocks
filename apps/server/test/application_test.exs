defmodule ApplicationTest do
  use ExUnit.Case
  doctest Server.Application

  test "should start and stop" do
    assert Server.Application.start([], []) |> elem(0) == :ok
    assert Server.Application.stop([]) == :ok
  end
end
