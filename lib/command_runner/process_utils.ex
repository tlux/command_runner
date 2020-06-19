defmodule CommandRunner.ProcessUtils do
  @moduledoc false

  @spec kill_os_process(port) :: :ok | :error
  def kill_os_process(port) do
    with {:os_pid, os_pid} <- Port.info(port, :os_pid),
         {_, 0} <-
           System.cmd("kill", ["-9", to_string(os_pid)], stderr_to_stdout: true) do
      :ok
    else
      _ -> :error
    end
  end
end
