defmodule CommandRunner.OSProcessHelper do
  @spec os_process_exists?(non_neg_integer) :: boolean
  def os_process_exists?(os_pid) when is_integer(os_pid) do
    # Taken from here:
    # https://stackoverflow.com/questions/3043978/how-to-check-if-a-process-id-pid-exists
    case System.cmd("kill", ["-0", to_string(os_pid)], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end
end
