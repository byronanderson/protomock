defmodule ProtoMockTest do
  use ExUnit.Case

  alias ProtoMock.VerificationError

  describe "defimpl" do
    test "when there is no existing impl for Protomock, it creates one" do
      defprotocol DefimplTest1 do
        def hello(impl)
      end

      ProtoMock.create_impl(DefimplTest1)

      protomock =
        ProtoMock.new()
        |> ProtoMock.expect(&DefimplTest1.hello/1, fn -> "hello, world!" end)

      assert DefimplTest1.hello(protomock) == "hello, world!"

      assert ProtoMock.verify!(protomock) == :ok
    end

    test "when there is already an impl defined, it raises an error" do
      defprotocol DefimplTest2 do
        def hello(impl)
      end

      ProtoMock.create_impl(DefimplTest2)

      msg = ~r"ProtoMock already has an implementation defined for protocol #{DefimplTest2}"

      assert_raise ProtoMock.ImplAlreadyDefinedError, msg, fn ->
        ProtoMock.create_impl(DefimplTest2)
      end
    end

    test "when the argument is not a protocol, it raises an error" do
      assert_raise ArgumentError, "Map is not a protocol", fn ->
        ProtoMock.create_impl(Map)
      end
    end
  end

  describe "expect" do
    test "works in the simple case" do
      protomock = mock_add()

      assert Calculator.add(protomock, 1, 2) == 3
    end

    test "is order-insensitive" do
      protomock =
        ProtoMock.new()
        |> ProtoMock.expect(&Calculator.add/3, 3, fn x, y -> x + y end)
        |> ProtoMock.expect(&Calculator.mult/3, 2, fn x, y -> x * y end)

      assert Calculator.add(protomock, 1, 1) == 2
      assert Calculator.mult(protomock, 1, 1) == 1
      assert Calculator.add(protomock, 2, 4) == 6
      assert Calculator.mult(protomock, 2, 4) == 8
      assert Calculator.add(protomock, 5, 4) == 9
    end

    test "allows asserting that the function has not been called" do
      protomock =
        ProtoMock.new()
        |> ProtoMock.expect(&Calculator.add/3, 0, fn x, y -> x + y end)

      msg = ~r"expected Calculator.add/3 to be called 0 times but it was called once"

      assert_raise ProtoMock.UnexpectedCallError, msg, fn ->
        Calculator.add(protomock, 2, 3) == 5
      end
    end

    test "can be 'recharged'" do
      protomock = mock_add()

      assert Calculator.add(protomock, 1, 2) == 3

      protomock |> ProtoMock.expect(&Calculator.add/3, 1, fn x, y -> x + y end)

      assert Calculator.add(protomock, 2, 2) == 4
    end

    test "raises if there are no expectations" do
      msg = ~r"expected Calculator.add\/3 to be called 0 times but it was called once"

      assert_raise ProtoMock.UnexpectedCallError, msg, fn ->
        Calculator.add(ProtoMock.new(), 2, 3) == 5
      end
    end

    test "raises if expectations are exceeded" do
      protomock = mock_add()

      assert Calculator.add(protomock, 1, 2) == 3

      msg = "expected Calculator.add/3 to be called once but it was called twice"

      assert_raise ProtoMock.UnexpectedCallError, msg, fn ->
        Calculator.add(protomock, 2, 3)
      end

      ProtoMock.expect(protomock, &Calculator.add/3, fn x, y -> x + y end)

      msg = "expected Calculator.add/3 to be called twice but it was called 3 times"

      assert_raise ProtoMock.UnexpectedCallError, msg, fn ->
        Calculator.add(protomock, 2, 3)
      end
    end
  end

  describe "verify" do
    test "with no expectations, it returns :ok" do
      protomock = ProtoMock.new()

      assert ProtoMock.verify!(protomock) == :ok
    end

    test "if expectations have been met, it returns :ok" do
      protomock = mock_add()

      Calculator.add(protomock, 1, 2)

      assert ProtoMock.verify!(protomock) == :ok
    end

    test "if expectations have not been met, it raises" do
      protomock = mock_add()

      msg = "expected Calculator.add/3 to be called once but it was called 0 times"

      assert_raise VerificationError, msg, fn ->
        ProtoMock.verify!(protomock)
      end
    end

    test "it 'recharges' when expectations 'recharge'" do
      protomock = mock_add()

      Calculator.add(protomock, 1, 2)

      assert ProtoMock.verify!(protomock) == :ok

      ProtoMock.expect(protomock, &Calculator.add/3, fn x, y -> x + y end)

      msg = "expected Calculator.add/3 to be called twice but it was called once"

      assert_raise VerificationError, msg, fn ->
        ProtoMock.verify!(protomock)
      end
    end

    test "it looks at all expected functions" do
      protomock =
        mock_add()
        |> ProtoMock.expect(&Calculator.mult/3, fn x, y -> x * y end)

      Calculator.add(protomock, 1, 2)

      msg = "expected Calculator.mult/3 to be called once but it was called 0 times"

      assert_raise VerificationError, msg, fn ->
        ProtoMock.verify!(protomock)
      end
    end

    test "it reports all errors at once" do
      protomock =
        mock_add()
        |> ProtoMock.expect(&Calculator.mult/3, fn x, y -> x * y end)

      msg1 = "expected Calculator.add/3 to be called once but it was called 0 times"
      msg2 = "expected Calculator.mult/3 to be called once but it was called 0 times"

      try do
        ProtoMock.verify!(protomock)
      rescue
        e in VerificationError ->
          assert e.message =~ msg1
          assert e.message =~ msg2
      else
        _ -> flunk("Expected VerificationError but did not get one")
      end
    end
  end

  describe "stub" do
    test "allows repeated invocations" do
      protomock = stub_add()

      assert Calculator.add(protomock, 1, 2) == 3
      assert Calculator.add(protomock, 3, 4) == 7
    end

    test "does not fail verification if not called" do
      protomock = stub_add()

      assert ProtoMock.verify!(protomock) == :ok
    end

    test "gives expectations precedence" do
      protomock =
        ProtoMock.new()
        |> ProtoMock.stub(&Calculator.add/3, fn x, y -> x + y end)
        |> ProtoMock.expect(&Calculator.add/3, fn _x, _y -> :expected end)

      assert Calculator.add(protomock, 1, 2) == :expected
    end

    test "a stub is called after all expectations are fulfilled" do
      protomock =
        ProtoMock.new()
        |> ProtoMock.stub(&Calculator.add/3, fn _x, _y -> :stubbed end)
        |> ProtoMock.expect(&Calculator.add/3, 3, fn _x, _y -> :expected end)

      assert Calculator.add(protomock, 1, 2) == :expected
      assert Calculator.add(protomock, 3, 4) == :expected
      assert Calculator.add(protomock, 5, 6) == :expected
      assert Calculator.add(protomock, 7, 8) == :stubbed
      assert Calculator.add(protomock, 9, 0) == :stubbed
    end

    test "overwrites earlier stubs" do
      protomock =
        ProtoMock.new()
        |> ProtoMock.stub(&Calculator.add/3, fn _x, _y -> :first end)
        |> ProtoMock.stub(&Calculator.add/3, fn _x, _y -> :second end)

      assert Calculator.add(protomock, 1, 2) == :second
    end
  end

  defp mock_add() do
    mock_add(ProtoMock.new())
  end

  defp mock_add(protomock) do
    protomock |> ProtoMock.expect(&Calculator.add/3, fn x, y -> x + y end)
  end

  defp stub_add() do
    ProtoMock.new()
    |> ProtoMock.stub(&Calculator.add/3, fn x, y -> x + y end)
  end
end
