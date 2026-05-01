defmodule MiakTechTest do
  use ExUnit.Case
  doctest MiakTech

  test "greets the world" do
    assert MiakTech.hello() == :world
  end
end
