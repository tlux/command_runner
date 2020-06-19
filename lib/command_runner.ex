defmodule CommandRunner do
  @moduledoc """
  A server to run Unix shell commands.

  ## Setup

  The recommended way is to use `CommandRunner` as part of your application
  supervision tree.

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            {CommandRunner, name: MyApp.CommandRunner}
          ]

          Supervisor.start_link(
            children,
            strategy: :one_for_one,
            name: MyApp.Supervisor
          )
        end
      end

  Alternatively, you can define your own command runner.

      defmodule MyApp.CommandRunner do
        use CommandRunner
      end

  You can also mount that in your supervision tree.

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            MyApp.CommandRunner
          ]

          Supervisor.start_link(
            children,
            strategy: :one_for_one,
            name: MyApp.Supervisor
          )
        end
      end
  """

  use GenServer

  alias CommandRunner.ProcessUtils
  alias CommandRunner.State

  @typedoc """
  Type describing the command runner server.
  """
  @type server :: GenServer.server()

  defmacro __using__(_opts) do
    quote location: :keep do
      @doc false
      @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
      def child_spec(_spec_opts) do
        %{
          id: __MODULE__,
          start: {CommandRunner, :start_link, [[name: __MODULE__]]}
        }
      end

      defoverridable child_spec: 1

      @doc """
      Starts the command runner.
      """
      @spec start_link() :: GenServer.on_start()
      def start_link do
        CommandRunner.start_link(name: __MODULE__)
      end

      @doc """
      Stops the command runner.
      """
      @spec stop(term) :: :ok
      def stop(reason \\ :normal) do
        CommandRunner.stop(__MODULE__, reason)
      end

      @doc """
      Runs a particular command and returns the exit code and result data.

      ## Options

      * `:cd` - Path to the working directory that the script is executed in.
      * `:env` - A map containing environment variables that are passed to the
        command.
      """
      @spec run_command(binary, Keyword.t(), reference) ::
              {exit_code :: integer, binary} | :running | :stopped
      def run_command(cmd, opts \\ [], ref \\ make_ref()) do
        CommandRunner.run_command(__MODULE__, cmd, opts, ref)
      end

      @doc """
      Determines whether the command with the specified ref is running on the
      server.

      ## Examples

          iex> ref = make_ref()
          ...> Task.async(fn ->
          ...>   CommandRunner.run_command(MyApp.Runner, "sleep 2", [], ref)
          ...> end)
          ...> CommandRunner.command_running?(MyApp.Runner, ref)
          true

          iex> CommandRunner.run_command(MyApp.Runner, "echo 'Hey!'", [], ref)
          ...> CommandRunner.command_running?(MyApp.Runner, ref)
          false
      """
      @spec command_running?(reference) :: boolean
      def command_running?(ref) do
        CommandRunner.command_running?(__MODULE__, ref)
      end

      @doc """
      Gets the OS process ID for the command with the specified ref on the given
      server.
      """
      @spec os_pid(reference) :: nil | non_neg_integer
      def os_pid(ref) do
        CommandRunner.os_pid(__MODULE__, ref)
      end

      @doc """
      Stops the command with the given ref and brutally kills the associated OS
      process.
      """
      @spec stop_command(reference) :: :ok
      def stop_command(ref) do
        CommandRunner.stop_command(__MODULE__, ref)
      end
    end
  end

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

  ## Options

  * `:cd` - Path to the working directory that the script is executed in.
  * `:env` - A map containing environment variables that are passed to the
    command.

  ## Examples

      iex> CommandRunner.run_command(MyApp.Runner, "echo 'Hello World'")
      {0, "Hello World\\n"}

      iex> CommandRunner.run_command(MyApp.Runner, "which foo")
      {1, ""}

  Only one command with the same ref can run in a single command runner process.

      iex> ref = make_ref()
      ...> Task.async(fn ->
      ...>   CommandRunner.run_command(MyApp.Runner, "sleep 2", [], ref)
      ...> end)
      ...> CommandRunner.run_command(MyApp.Runner, "echo 'Hello'", [], ref)
      :running

  Other processes may stop a command. The caller is notified about that.

      iex> ref = make_ref()
      ...> task = Task.async(fn ->
      ...>   CommandRunner.run_command(MyApp.Runner, "sleep 2", [], ref)
      ...> end)
      ...> CommandRunner.stop_command(MyApp.Runner, ref)
      ...> Task.await(task)
      :stopped
  """
  @spec run_command(server, binary, Keyword.t(), reference) ::
          {exit_code :: integer, binary} | :running | :stopped
  def run_command(
        server,
        cmd,
        opts \\ [],
        ref \\ make_ref()
      ) do
    GenServer.call(
      server,
      {:run_command, cmd, opts, ref},
      :infinity
    )
  end

  @doc """
  Determines whether the command with the specified ref is running on the given
  server.

  ## Examples

      iex> ref = make_ref()
      ...> Task.async(fn ->
      ...>   CommandRunner.run_command(MyApp.Runner, "sleep 2", [], ref)
      ...> end)
      ...> CommandRunner.command_running?(MyApp.Runner, ref)
      true

      iex> CommandRunner.run_command(MyApp.Runner, "echo 'Hey!'", [], ref)
      ...> CommandRunner.command_running?(MyApp.Runner, ref)
      false
  """
  @spec command_running?(server, reference) :: boolean
  def command_running?(server, ref) do
    GenServer.call(server, {:command_running?, ref})
  end

  @doc """
  Gets the OS process ID for the command with the specified ref on the given
  server.

  ## Examples

      iex> ref = make_ref()
      ...> Task.async(fn ->
      ...>   CommandRunner.run_command(MyApp.Runner, "sleep 2", [], ref)
      ...> end)
      ...> CommandRunner.os_pid(MyApp.Runner, ref)
      6458

      iex> CommandRunner.run_command(MyApp.Runner, "echo 'Hey!'", [], ref)
      nil
  """
  @spec os_pid(server, reference) :: nil | non_neg_integer
  def os_pid(server, ref) do
    GenServer.call(server, {:os_pid, ref})
  end

  @doc """
  Stops the command with the given ref and brutally kills the associated OS
  process.

  # Example

      iex> ref = make_ref()
      ...> Task.async(fn ->
      ...>   CommandRunner.run_command(MyApp.Runner, "sleep 2", [], ref)
      ...> end)
      ...> CommandRunner.stop_command(MyApp.Runner, ref)
      :ok
  """
  @spec stop_command(server, reference) :: :ok
  def stop_command(server, ref) do
    GenServer.call(server, {:stop_command, ref})
  end

  # Callbacks

  @impl true
  def init(_init_arg) do
    {:ok, %State{}}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.ports, fn {port, %{client: client}} ->
      ProcessUtils.kill_os_process(port)
      GenServer.reply(client, :stopped)
    end)
  end

  @impl true
  def handle_call(
        {:run_command, cmd, opts, ref},
        from,
        state
      ) do
    if State.entry_exists?(state, ref) do
      {:reply, :running, state}
    else
      port =
        Port.open({:spawn, cmd}, [
          :binary,
          :exit_status,
          :stderr_to_stdout | open_opts(opts)
        ])

      {:noreply, State.put_entry(state, ref, port, from)}
    end
  end

  def handle_call({:command_running?, ref}, _from, state) do
    {:reply, State.entry_exists?(state, ref), state}
  end

  def handle_call({:os_pid, ref}, _from, state) do
    case State.fetch_entry_by_ref(state, ref) do
      {:ok, %{port: port}} ->
        {:os_pid, os_pid} = Port.info(port, :os_pid)
        {:reply, os_pid, state}

      _ ->
        {:reply, nil, state}
    end
  end

  def handle_call({:stop_command, ref}, _from, state) do
    case State.fetch_entry_by_ref(state, ref) do
      {:ok, %{client: client, port: port}} ->
        ProcessUtils.kill_os_process(port)
        GenServer.reply(client, :stopped)
        {:reply, :ok, State.delete_entry(state, ref, port)}

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

  @impl true
  def handle_info({port, {:data, data}}, state) do
    case State.fetch_entry_by_port(state, port) do
      {:ok, %{result: {acc, fun}}} ->
        new_acc = fun.(acc, {:cont, data})
        {:noreply, State.put_result(state, port, {new_acc, fun})}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({port, {:exit_status, exit_status}}, state) do
    case State.fetch_entry_by_port(state, port) do
      {:ok, %{client: client, ref: ref, result: {acc, fun}}} ->
        GenServer.reply(client, {exit_status, fun.(acc, :done)})
        {:noreply, State.delete_entry(state, ref, port)}

      :error ->
        {:noreply, state}
    end
  end
end
