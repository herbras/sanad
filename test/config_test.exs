defmodule Sanad.ConfigTest do
  use ExUnit.Case, async: true

  alias Sanad.Config

  test "normalizes nested keyword lists to maps" do
    assert Config.normalize(chat: [provider: :openai], agent: %{provider: :pi}) ==
             %{chat: %{provider: :openai}, agent: %{provider: :pi}}
  end

  test "keeps plain lists and normalizes empty lists to empty config maps" do
    assert Config.normalize(%{a: []}) == %{a: %{}}
    assert Config.normalize(%{a: [1, 2]}) == %{a: [1, 2]}
    assert Config.normalize(%{a: ["x"]}) == %{a: ["x"]}
  end

  test "leaves structs untouched" do
    uri = URI.parse("https://example.com")
    assert Config.normalize(%{a: uri}).a == uri
  end
end
