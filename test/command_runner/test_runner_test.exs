defmodule CommandRunner.CommandRunnerTest do
  use ExUnit.Case

  import CommandRunner.OSProcessHelper
  import Liveness

  alias CommandRunner.TestRunner

  setup do
    start_supervised!(TestRunner)
    :ok
  end

  describe "stop/0" do
    test "stop associated OS processes" do
      task_supervisor = start_supervised!(Task.Supervisor)
      production_command_ref = make_ref()
      staging_command_ref = make_ref()

      task_a =
        Task.Supervisor.async(task_supervisor, fn ->
          TestRunner.run_command(
            "sleep 2",
            [],
            production_command_ref
          )
        end)

      task_b =
        Task.Supervisor.async(task_supervisor, fn ->
          TestRunner.run_command("sleep 2", [], staging_command_ref)
        end)

      assert eventually(fn ->
               TestRunner.command_running?(production_command_ref) &&
                 TestRunner.command_running?(staging_command_ref)
             end)

      production_os_pid = TestRunner.os_pid(production_command_ref)
      staging_os_pid = TestRunner.os_pid(staging_command_ref)

      assert os_process_exists?(production_os_pid)
      assert os_process_exists?(staging_os_pid)
      assert TestRunner.stop() == :ok
      refute os_process_exists?(production_os_pid)
      refute os_process_exists?(staging_os_pid)

      assert Task.await(task_a) == :stopped
      assert Task.await(task_b) == :stopped
    end
  end

  describe "stop/1" do
    test "stop associated OS processes" do
      task_supervisor = start_supervised!(Task.Supervisor)
      production_command_ref = make_ref()
      staging_command_ref = make_ref()

      task_a =
        Task.Supervisor.async(task_supervisor, fn ->
          TestRunner.run_command(
            "sleep 2",
            [],
            production_command_ref
          )
        end)

      task_b =
        Task.Supervisor.async(task_supervisor, fn ->
          TestRunner.run_command("sleep 2", [], staging_command_ref)
        end)

      assert eventually(fn ->
               TestRunner.command_running?(production_command_ref) &&
                 TestRunner.command_running?(staging_command_ref)
             end)

      production_os_pid = TestRunner.os_pid(production_command_ref)
      staging_os_pid = TestRunner.os_pid(staging_command_ref)

      assert os_process_exists?(production_os_pid)
      assert os_process_exists?(staging_os_pid)
      assert TestRunner.stop(:normal) == :ok
      refute os_process_exists?(production_os_pid)
      refute os_process_exists?(staging_os_pid)

      assert Task.await(task_a) == :stopped
      assert Task.await(task_b) == :stopped
    end
  end

  describe "run_command/1" do
    test "successful command" do
      assert TestRunner.run_command("./test/fixtures/success_script.sh") ==
               {0, "Everything OK!\n"}
    end

    test "successful command with working dir" do
      File.cd!("test/fixtures", fn ->
        assert TestRunner.run_command("./success_script.sh") ==
                 {0, "Everything OK!\n"}
      end)
    end

    test "auto-generate command ref" do
      task_supervisor = start_supervised!(Task.Supervisor)

      Task.Supervisor.async(task_supervisor, fn ->
        TestRunner.run_command("sleep 1")
      end)

      assert eventually(fn ->
               TestRunner
               |> :sys.get_state()
               |> Map.fetch!(:refs)
               |> Map.keys()
               |> List.first()
               |> is_reference()
             end)
    end

    test "failed command" do
      File.cd!("test/fixtures", fn ->
        assert TestRunner.run_command("./error_script.sh") ==
                 {1, "Something went wrong\n"}
      end)
    end

    test "allow parallel execution for different refs" do
      task_supervisor = start_supervised!(Task.Supervisor)

      task_a =
        Task.Supervisor.async(task_supervisor, fn ->
          TestRunner.run_command("sleep 0.3")
        end)

      task_b =
        Task.Supervisor.async(task_supervisor, fn ->
          TestRunner.run_command("./test/fixtures/success_script.sh")
        end)

      assert Task.await(task_a) == {0, ""}
      assert Task.await(task_b) == {0, "Everything OK!\n"}
    end
  end

  describe "run_command/2" do
    test "change working dir" do
      assert TestRunner.run_command("./success_script.sh", cd: "test/fixtures") ==
               {0, "Everything OK!\n"}
    end

    test "use env vars" do
      File.cd!("test/fixtures", fn ->
        assert TestRunner.run_command(
                 "./success_script_with_env_vars.sh",
                 env: [{"FOO", "Tobi"}]
               ) == {0, "Hello, Tobi!\n"}

        assert TestRunner.run_command(
                 "./success_script_with_env_vars.sh",
                 env: [{"FOO", 123}]
               ) == {0, "Hello, 123!\n"}

        assert TestRunner.run_command(
                 "./success_script_with_env_vars.sh",
                 env: %{"FOO" => "Fernando"}
               ) == {0, "Hello, Fernando!\n"}

        assert TestRunner.run_command(
                 "./success_script_with_env_vars.sh",
                 env: %{"FOO" => nil}
               ) == {0, "Hello, !\n"}
      end)
    end
  end

  describe "run_command/3" do
    test "prevent parallel execution for same ref" do
      task_supervisor = start_supervised!(Task.Supervisor)
      command_ref = make_ref()

      task_a =
        Task.Supervisor.async(task_supervisor, fn ->
          TestRunner.run_command("sleep 0.5", [], command_ref)
        end)

      task_b =
        Task.Supervisor.async(task_supervisor, fn ->
          TestRunner.run_command(
            "./test/fixtures/success_script.sh",
            [],
            command_ref
          )
        end)

      assert Task.await(task_a) == {0, ""}
      assert Task.await(task_b) == :running
    end
  end

  describe "command_running?/1" do
    test "true when command running for env" do
      task_supervisor = start_supervised!(Task.Supervisor)
      command_ref = make_ref()

      Task.Supervisor.async(task_supervisor, fn ->
        TestRunner.run_command("sleep 0.2", [], command_ref)
      end)

      assert eventually(fn ->
               TestRunner.command_running?(command_ref)
             end)
    end

    test "false when no command running for env" do
      assert TestRunner.command_running?(make_ref()) == false
    end
  end

  describe "os_pid/1" do
    test "get OS process ID when command running for env" do
      task_supervisor = start_supervised!(Task.Supervisor)
      command_ref = make_ref()

      command_task =
        Task.Supervisor.async(task_supervisor, fn ->
          TestRunner.run_command("sleep 0.2", [], command_ref)
        end)

      assert eventually(fn ->
               TestRunner.command_running?(command_ref)
             end)

      os_pid = TestRunner.os_pid(command_ref)

      assert os_pid
      assert is_integer(os_pid)
      assert os_process_exists?(os_pid)

      Task.await(command_task)
    end

    test "nil when no command running for env" do
      assert TestRunner.os_pid(make_ref()) == nil
    end
  end

  describe "stop_command/1" do
    test "kill running command" do
      task_supervisor = start_supervised!(Task.Supervisor)
      command_ref = make_ref()

      # Task containing a long running command
      command_task =
        Task.Supervisor.async(task_supervisor, fn ->
          TestRunner.run_command("sleep 2", [], command_ref)
        end)

      assert eventually(fn ->
               TestRunner.command_running?(command_ref)
             end)

      # Find out the OS process ID for the running command to verify
      # it is currently running and to verify whether it has been killed later
      # on in the test
      os_pid = TestRunner.os_pid(command_ref)
      assert os_process_exists?(os_pid)

      # Kills the command
      assert TestRunner.stop_command(command_ref) == :ok
      refute os_process_exists?(os_pid)

      assert Task.await(command_task) == :stopped
    end

    test "ok when no command running" do
      assert TestRunner.stop_command(make_ref()) == :ok
    end
  end
end
