defmodule Matterlix.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:matterlix, :auto_supervise, true) do
        [{Matterlix.Matter, Application.get_all_env(:matterlix)}]
      else
        []
      end

    opts = [strategy: :one_for_one, name: Matterlix.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
