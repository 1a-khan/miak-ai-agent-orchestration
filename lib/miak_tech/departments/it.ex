defmodule MiakTech.Department.IT do
  use Supervisor

  alias MiakTech.Agent.{Programmer, Administrator}

  def start_link(_), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  def init(_) do
    Supervisor.init([Programmer, Administrator], strategy: :one_for_one)
  end

  def handle_task(task) do
    prog  = Task.async(fn -> Programmer.handle_task(task) end)
    admin = Task.async(fn -> Administrator.handle_task(task) end)
    %{
      programmer:    Task.await(prog,  30_000),
      administrator: Task.await(admin, 30_000)
    }
  end
end
