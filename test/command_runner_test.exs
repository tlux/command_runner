defmodule CommandRunnerTest do
  use ExUnit.Case

  import CommandRunner.OSProcessHelper
  import Liveness

  setup do
    {:ok, server: start_supervised!(CommandRunner)}
  end

  describe "stop/1" do
    test "stop associated OS processes", %{server: server} do
      task_supervisor = start_supervised!(Task.Supervisor)
      production_command_ref = make_ref()
      staging_command_ref = make_ref()

      task_a =
        Task.Supervisor.async(task_supervisor, fn ->
          CommandRunner.run_command(
            server,
            "sleep 2",
            [],
            production_command_ref
          )
        end)

      task_b =
        Task.Supervisor.async(task_supervisor, fn ->
          CommandRunner.run_command(server, "sleep 2", [], staging_command_ref)
        end)

      assert eventually(fn ->
               CommandRunner.command_running?(server, production_command_ref) &&
                 CommandRunner.command_running?(server, staging_command_ref)
             end)

      production_os_pid = CommandRunner.os_pid(server, production_command_ref)
      staging_os_pid = CommandRunner.os_pid(server, staging_command_ref)

      assert os_process_exists?(production_os_pid)
      assert os_process_exists?(staging_os_pid)
      assert CommandRunner.stop(server) == :ok
      refute os_process_exists?(production_os_pid)
      refute os_process_exists?(staging_os_pid)

      assert Task.await(task_a) == :stopped
      assert Task.await(task_b) == :stopped
    end
  end

  describe "stop/2" do
    test "stop associated OS processes", %{server: server} do
      task_supervisor = start_supervised!(Task.Supervisor)
      production_command_ref = make_ref()
      staging_command_ref = make_ref()

      task_a =
        Task.Supervisor.async(task_supervisor, fn ->
          CommandRunner.run_command(
            server,
            "sleep 2",
            [],
            production_command_ref
          )
        end)

      task_b =
        Task.Supervisor.async(task_supervisor, fn ->
          CommandRunner.run_command(server, "sleep 2", [], staging_command_ref)
        end)

      assert eventually(fn ->
               CommandRunner.command_running?(server, production_command_ref) &&
                 CommandRunner.command_running?(server, staging_command_ref)
             end)

      production_os_pid = CommandRunner.os_pid(server, production_command_ref)
      staging_os_pid = CommandRunner.os_pid(server, staging_command_ref)

      assert os_process_exists?(production_os_pid)
      assert os_process_exists?(staging_os_pid)
      assert CommandRunner.stop(server, :normal) == :ok
      refute os_process_exists?(production_os_pid)
      refute os_process_exists?(staging_os_pid)

      assert Task.await(task_a) == :stopped
      assert Task.await(task_b) == :stopped
    end
  end

  describe "run_command/2" do
    test "successful command", %{server: server} do
      assert CommandRunner.run_command(
               server,
               "./test/fixtures/success_script.sh"
             ) == {0, "Everything OK!\n"}
    end

    test "successful command with working dir", %{server: server} do
      File.cd!("test/fixtures", fn ->
        assert CommandRunner.run_command(server, "./success_script.sh") ==
                 {0, "Everything OK!\n"}
      end)
    end

    test "auto-generate command ref", %{server: server} do
      task_supervisor = start_supervised!(Task.Supervisor)

      Task.Supervisor.async(task_supervisor, fn ->
        CommandRunner.run_command(server, "sleep 1")
      end)

      assert eventually(fn ->
               server
               |> :sys.get_state()
               |> Map.fetch!(:refs)
               |> Map.keys()
               |> List.first()
               |> is_reference()
             end)
    end

    test "failed command", %{server: server} do
      File.cd!("test/fixtures", fn ->
        assert CommandRunner.run_command(server, "./error_script.sh") ==
                 {1, "Something went wrong\n"}
      end)
    end

    test "allow parallel execution for different refs", %{server: server} do
      task_supervisor = start_supervised!(Task.Supervisor)

      task_a =
        Task.Supervisor.async(task_supervisor, fn ->
          CommandRunner.run_command(server, "sleep 0.3")
        end)

      task_b =
        Task.Supervisor.async(task_supervisor, fn ->
          CommandRunner.run_command(server, "./test/fixtures/success_script.sh")
        end)

      assert Task.await(task_a) == {0, ""}
      assert Task.await(task_b) == {0, "Everything OK!\n"}
    end
  end

  describe "run_command/3" do
    test "change working dir", %{server: server} do
      assert CommandRunner.run_command(server, "./success_script.sh",
               cd: "test/fixtures"
             ) == {0, "Everything OK!\n"}
    end

    test "use env vars", %{server: server} do
      File.cd!("test/fixtures", fn ->
        assert CommandRunner.run_command(
                 server,
                 "./success_script_with_env_vars.sh",
                 env: [{"FOO", "Tobi"}]
               ) == {0, "Hello, Tobi!\n"}

        assert CommandRunner.run_command(
                 server,
                 "./success_script_with_env_vars.sh",
                 env: [{"FOO", 123}]
               ) == {0, "Hello, 123!\n"}

        assert CommandRunner.run_command(
                 server,
                 "./success_script_with_env_vars.sh",
                 env: %{"FOO" => "Fernando"}
               ) == {0, "Hello, Fernando!\n"}

        assert CommandRunner.run_command(
                 server,
                 "./success_script_with_env_vars.sh",
                 env: %{"FOO" => nil}
               ) == {0, "Hello, !\n"}
      end)
    end
  end

  describe "run_command/4" do
    test "prevent parallel execution for same ref", %{server: server} do
      task_supervisor = start_supervised!(Task.Supervisor)
      command_ref = make_ref()

      task_a =
        Task.Supervisor.async(task_supervisor, fn ->
          CommandRunner.run_command(server, "sleep 0.5", [], command_ref)
        end)

      task_b =
        Task.Supervisor.async(task_supervisor, fn ->
          CommandRunner.run_command(
            server,
            "./test/fixtures/success_script.sh",
            [],
            command_ref
          )
        end)

      assert Task.await(task_a) == {0, ""}
      assert Task.await(task_b) == :locked
    end
  end

  describe "command_running?/2" do
    test "true when command running for env", %{server: server} do
      task_supervisor = start_supervised!(Task.Supervisor)
      command_ref = make_ref()

      Task.Supervisor.async(task_supervisor, fn ->
        CommandRunner.run_command(server, "sleep 0.2", [], command_ref)
      end)

      assert eventually(fn ->
               CommandRunner.command_running?(server, command_ref)
             end)
    end

    test "false when no command running for env", %{server: server} do
      assert CommandRunner.command_running?(server, make_ref()) == false
    end
  end

  describe "os_pid/2" do
    test "get OS process ID when command running for env", %{server: server} do
      task_supervisor = start_supervised!(Task.Supervisor)
      command_ref = make_ref()

      command_task =
        Task.Supervisor.async(task_supervisor, fn ->
          CommandRunner.run_command(server, "sleep 0.2", [], command_ref)
        end)

      assert eventually(fn ->
               CommandRunner.command_running?(server, command_ref)
             end)

      os_pid = CommandRunner.os_pid(server, command_ref)

      assert os_pid
      assert is_integer(os_pid)
      assert os_process_exists?(os_pid)

      Task.await(command_task)
    end

    test "nil when no command running for env", %{server: server} do
      assert CommandRunner.os_pid(server, make_ref()) == nil
    end
  end

  describe "stop_command/2" do
    test "kill running command", %{server: server} do
      task_supervisor = start_supervised!(Task.Supervisor)
      command_ref = make_ref()

      # Task containing a long running command
      command_task =
        Task.Supervisor.async(task_supervisor, fn ->
          CommandRunner.run_command(server, "sleep 2", [], command_ref)
        end)

      assert eventually(fn ->
               CommandRunner.command_running?(server, command_ref)
             end)

      # Find out the OS process ID for the running command to verify
      # it is currently running and to verify whether it has been killed later
      # on in the test
      os_pid = CommandRunner.os_pid(server, command_ref)
      assert os_process_exists?(os_pid)

      # Kills the command
      assert CommandRunner.stop_command(server, command_ref) == :ok
      refute os_process_exists?(os_pid)

      assert Task.await(command_task) == :stopped
    end

    test "ok when no command running", %{server: server} do
      assert CommandRunner.stop_command(server, make_ref()) == :ok
    end
  end
end
