defmodule Membrane.Element.IVF do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = []
    opts = [strategy: :one_for_one, name: Membrane.Element.IVF]
    Supervisor.start_link(children, opts)
  end
end
