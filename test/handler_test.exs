defmodule Matterlix.HandlerTest do
  use ExUnit.Case, async: false

  defmodule TestHandler do
    @behaviour Matterlix.Handler

    @impl true
    def handle_attribute_change(endpoint_id, cluster_id, attribute_id, type, value) do
      send(self(), {:handled, endpoint_id, cluster_id, attribute_id, type, value})
      :ok
    end
  end

  defmodule ErrorHandler do
    @behaviour Matterlix.Handler

    @impl true
    def handle_attribute_change(_ep, _cl, _attr, _type, _val) do
      {:error, :test_error}
    end
  end

  describe "Handler behaviour dispatch" do
    test "attribute_changed dispatches to configured handler" do
      # We need the handler to send to the test process, but handle_attribute_change
      # runs inside the GenServer. Use an Agent to capture calls instead.
      {:ok, agent} = Agent.start_link(fn -> [] end)

      handler_mod = create_capturing_handler(agent)

      Application.put_env(:matterlix, :handler, handler_mod)

      name = :"handler_test_#{System.unique_integer([:positive])}"
      {:ok, pid} = Matterlix.Matter.start_link(name: name)

      send(pid, {:attribute_changed, 1, 0x0006, 0x0000, 0x10, true})
      Process.sleep(50)

      calls = Agent.get(agent, & &1)
      assert [{1, 0x0006, 0x0000, 0x10, true}] = calls

      GenServer.stop(pid)
      Agent.stop(agent)
      Application.delete_env(:matterlix, :handler)
    end

    test "handler errors are logged but don't crash the GenServer" do
      Application.put_env(:matterlix, :handler, ErrorHandler)

      name = :"handler_err_#{System.unique_integer([:positive])}"
      {:ok, pid} = Matterlix.Matter.start_link(name: name)

      send(pid, {:attribute_changed, 1, 0x0006, 0x0000, 0x10, true})
      Process.sleep(50)

      assert Process.alive?(pid)

      GenServer.stop(pid)
      Application.delete_env(:matterlix, :handler)
    end

    test "add_network dispatches to handler if callback is implemented" do
      {:ok, agent} = Agent.start_link(fn -> [] end)

      handler_mod = create_network_handler(agent)

      Application.put_env(:matterlix, :handler, handler_mod)

      name = :"handler_net_#{System.unique_integer([:positive])}"
      {:ok, pid} = Matterlix.Matter.start_link(name: name)

      send(pid, {:add_network, "TestSSID", "password123"})
      Process.sleep(50)

      calls = Agent.get(agent, & &1)
      assert [{"TestSSID", "password123"}] = calls

      GenServer.stop(pid)
      Agent.stop(agent)
      Application.delete_env(:matterlix, :handler)
    end
  end

  describe "Default handler" do
    test "logs attribute changes without crashing" do
      name = :"handler_default_#{System.unique_integer([:positive])}"
      {:ok, pid} = Matterlix.Matter.start_link(name: name)

      send(pid, {:attribute_changed, 1, 0x0006, 0x0000, 0x10, true})
      Process.sleep(50)

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  # Creates a handler module that captures calls via an Agent
  defp create_capturing_handler(agent) do
    module_name = :"TestCapturingHandler_#{System.unique_integer([:positive])}"

    Module.create(
      module_name,
      quote do
        @behaviour Matterlix.Handler

        @impl true
        def handle_attribute_change(ep, cl, attr, type, val) do
          Agent.update(unquote(agent), fn calls -> calls ++ [{ep, cl, attr, type, val}] end)
          :ok
        end
      end,
      Macro.Env.location(__ENV__)
    )

    module_name
  end

  defp create_network_handler(agent) do
    module_name = :"TestNetworkHandler_#{System.unique_integer([:positive])}"

    Module.create(
      module_name,
      quote do
        @behaviour Matterlix.Handler

        @impl true
        def handle_attribute_change(_ep, _cl, _attr, _type, _val), do: :ok

        @impl true
        def handle_network_added(ssid, credentials) do
          Agent.update(unquote(agent), fn calls -> calls ++ [{ssid, credentials}] end)
          :ok
        end
      end,
      Macro.Env.location(__ENV__)
    )

    module_name
  end
end
