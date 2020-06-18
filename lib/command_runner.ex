defmodule CommandRunner do
  @moduledoc """
  A server to run shell commands.
  """

  use GenServer

  @typedoc """
  Type describing the command runner server.
  """
  @type server :: GenServer.server()

  @doc """
  Starts a command runner.
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Stops the given command runner and terminates all running commands.
  """
  @spec stop(server, term) :: :ok
  def stop(server, reason \\ :normal) do
    GenServer.stop(server, reason)
  end

  @doc """
  Runs a particular command and returns the exit code and result data.
  """
  @spec run_command(server, binary, Keyword.t(), reference) ::
          {exit_code :: integer, binary} | :locked | :stopped
  def run_command(
        server,
        cmd,
        opts \\ [],
        command_ref \\ make_ref()
      ) do
    GenServer.call(
      server,
      {:run_command, cmd, opts, command_ref},
      :infinity
    )
  end

  @doc """
  Determines whether the command with the specified ref is running on the given
  server.
  """
  @spec command_running?(server, reference) :: boolean
  def command_running?(server, command_ref) do
    GenServer.call(server, {:command_running?, command_ref})
  end

  @doc """
  Gets the OS process ID for the command with the specified ref on the given
  server.
  """
  @spec os_pid(server, reference) :: nil | non_neg_integer
  def os_pid(server, command_ref) do
    GenServer.call(server, {:os_pid, command_ref})
  end

  @doc """
  Stops the command with the given ref and brutally kills the associated OS
  process.
  """
  @spec stop_command(server, reference) :: :ok
  def stop_command(server, command_ref) do
    GenServer.call(server, {:stop_command, command_ref})
  end

  # Callbacks

  @impl true
  def init(:ok) do
    {:ok, %{commands: %{}, ports: %{}}}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.ports, fn {port, %{client: client}} ->
      brutal_kill_os_process(port)
      GenServer.reply(client, :stopped)
    end)
  end

  @impl true
  def handle_call(
        {:run_command, cmd, opts, command_ref},
        from,
        state
      ) do
    if Map.has_key?(state.commands, command_ref) do
      {:reply, :locked, state}
    else
      port =
        Port.open({:spawn, cmd}, [
          :binary,
          :exit_status,
          :stderr_to_stdout | open_opts(opts)
        ])

      {:noreply,
       %{
         commands:
           Map.put(state.commands, command_ref, %{client: from, port: port}),
         ports:
           Map.put(state.ports, port, %{
             client: from,
             command_ref: command_ref,
             result: Collectable.into("")
           })
       }}
    end
  end

  def handle_call({:command_running?, command_ref}, _from, state) do
    {:reply, Map.has_key?(state.commands, command_ref), state}
  end

  def handle_call({:os_pid, command_ref}, _from, state) do
    case Map.fetch(state.commands, command_ref) do
      {:ok, %{port: port}} ->
        {:os_pid, os_pid} = Port.info(port, :os_pid)
        {:reply, os_pid, state}

      _ ->
        {:reply, nil, state}
    end
  end

  def handle_call({:stop_command, command_ref}, _from, state) do
    case Map.fetch(state.commands, command_ref) do
      {:ok, %{client: client, port: port}} ->
        brutal_kill_os_process(port)
        GenServer.reply(client, :stopped)

        {:reply, :ok,
         %{
           commands: Map.delete(state.commands, command_ref),
           ports: Map.delete(state.ports, port)
         }}

      :error ->
        {:reply, :ok, state}
    end
  end

  defp open_opts(opts) do
    for opt <- opts do
      with {:env, env} <- opt do
        {:env,
         Enum.into(env, [], fn
           {key, nil} -> {to_charlist(key), false}
           {key, value} -> {to_charlist(key), to_charlist(value)}
         end)}
      end
    end
  end

  defp brutal_kill_os_process(port) do
    with {:os_pid, os_pid} <- Port.info(port, :os_pid) do
      System.cmd("kill", ["-9", to_string(os_pid)], stderr_to_stdout: true)
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, state) do
    case Map.fetch(state.ports, port) do
      {:ok, %{result: {acc, fun}}} ->
        new_acc = fun.(acc, {:cont, data})
        {:noreply, put_in(state, [:ports, port, :result], {new_acc, fun})}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({port, {:exit_status, exit_status}}, state) do
    case Map.fetch(state.ports, port) do
      {:ok, %{client: client, command_ref: command_ref, result: {acc, fun}}} ->
        result = {exit_status, fun.(acc, :done)}
        GenServer.reply(client, result)

        {:noreply,
         %{
           commands: Map.delete(state.commands, command_ref),
           ports: Map.delete(state.ports, port)
         }}

      :error ->
        {:noreply, state}
    end
  end
end
