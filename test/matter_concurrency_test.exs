defmodule Matterlix.Matter.ConcurrencyTest do
  use ExUnit.Case, async: false
  alias Matterlix.Matter.NIF

  @moduletag :slow

  describe "concurrent NIF operations" do
    test "concurrent init calls are safe" do
      # Spawn multiple processes calling init simultaneously
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            {:ok, ctx} = NIF.nif_init()
            {:ok, info} = NIF.nif_get_info(ctx)
            assert info.initialized == true
            ctx
          end)
        end

      contexts = Task.await_many(tasks, 5000)
      assert length(contexts) == 10

      # All contexts should be valid references
      Enum.each(contexts, fn ctx ->
        assert is_reference(ctx)
      end)
    end

    test "concurrent get_info calls are safe" do
      {:ok, ctx} = NIF.nif_init()

      tasks =
        for _ <- 1..50 do
          Task.async(fn ->
            {:ok, info} = NIF.nif_get_info(ctx)
            assert info.initialized == true
            :ok
          end)
        end

      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, &(&1 == :ok))
    end

    test "concurrent callback registration is safe" do
      {:ok, ctx} = NIF.nif_init()

      # Multiple processes trying to register
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            NIF.nif_register_callback(ctx)
          end)
        end

      results = Task.await_many(tasks, 5000)
      # All should succeed (last one wins)
      assert Enum.all?(results, &(&1 == :ok))

      # Note: After Tasks exit, the down callback clears the listener
      # This tests that concurrent registration doesn't crash
      # To have a listener, we need to register from the test process
      :ok = NIF.nif_register_callback(ctx)
      {:ok, info} = NIF.nif_get_info(ctx)
      assert info.has_listener == true
    end
  end

  describe "concurrent GenServer operations" do
    test "concurrent GenServer start_link calls" do
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            name = String.to_atom("matter_test_#{i}")
            {:ok, pid} = Matterlix.Matter.start_link(name: name)
            pid
          end)
        end

      pids = Task.await_many(tasks, 5000)
      assert length(pids) == 5

      # Cleanup
      Enum.each(pids, fn pid ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)
    end

    test "concurrent operations on single GenServer" do
      {:ok, pid} = Matterlix.Matter.start_link()

      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            case rem(i, 4) do
              0 -> Matterlix.Matter.get_info(pid)
              1 -> Matterlix.Matter.get_setup_payload(pid)
              2 -> Matterlix.Matter.set_commissioning_info(pid, 20_202_021, rem(i, 4095))
              3 -> Matterlix.Matter.open_commissioning_window(pid, 60)
            end
          end)
        end

      results = Task.await_many(tasks, 10_000)
      # All should complete without crash
      assert length(results) == 20

      GenServer.stop(pid)
    end
  end

  describe "stress testing" do
    @tag timeout: 30_000
    test "rapid init/destroy cycles" do
      for _ <- 1..100 do
        {:ok, ctx} = NIF.nif_init()
        {:ok, _info} = NIF.nif_get_info(ctx)
        # Context will be garbage collected
      end

      # Force garbage collection
      :erlang.garbage_collect()

      # Should still work after many cycles
      {:ok, ctx} = NIF.nif_init()
      {:ok, info} = NIF.nif_get_info(ctx)
      assert info.initialized == true
    end

    @tag timeout: 30_000
    test "rapid callback registration cycles" do
      {:ok, ctx} = NIF.nif_init()

      for _ <- 1..100 do
        :ok = NIF.nif_register_callback(ctx)
      end

      {:ok, info} = NIF.nif_get_info(ctx)
      assert info.has_listener == true
    end
  end
end
