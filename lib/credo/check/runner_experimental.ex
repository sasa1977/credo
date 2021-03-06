defmodule Credo.Check.RunnerExperimental do
  @moduledoc false

  # This module is responsible for running checks based on the context represented
  # by the current `Credo.Execution`.

  alias Credo.CLI.Output.UI
  alias Credo.Execution

  @doc """
  Runs all checks on all source files (according to the config).
  """
  def run(source_files, exec) when is_list(source_files) do
    check_tuples =
      exec
      |> Execution.checks()
      |> warn_about_ineffective_patterns(exec)
      |> fix_deprecated_notation_for_checks_without_params()

    Credo.Check.Worker.run(check_tuples, exec.max_concurrent_check_runs, fn check_tuple ->
      run_check(exec, check_tuple)
    end)

    :ok
  end

  defp run_check(%Execution{debug: true} = exec, {check, params}) do
    Execution.ExecutionTiming.run(&do_run_check/2, [exec, {check, params}])
    |> Execution.ExecutionTiming.append(exec, task: exec.current_task, check: check)
  end

  defp run_check(exec, {check, params}) do
    do_run_check(exec, {check, params})
  end

  defp do_run_check(exec, {check, params}) do
    source_files = Execution.get_source_files(exec)

    try do
      check.run_on_all_source_files(exec, source_files, params)
    rescue
      error ->
        warn_about_failed_run(check, source_files)

        if exec.crash_on_error do
          reraise error, System.stacktrace()
        else
          []
        end
    end
  end

  defp warn_about_failed_run(check, %Credo.SourceFile{} = source_file) do
    UI.warn("Error while running #{check} on #{source_file.filename}")
  end

  defp warn_about_failed_run(check, _) do
    UI.warn("Error while running #{check}")
  end

  defp fix_deprecated_notation_for_checks_without_params(checks) do
    Enum.map(checks, fn
      {check} -> {check, []}
      {check, params} -> {check, params}
    end)
  end

  defp warn_about_ineffective_patterns(
         {checks, _included_checks, []},
         %Execution{ignore_checks: [_ | _] = ignore_checks}
       ) do
    UI.warn([
      :red,
      "A pattern was given to ignore checks, but it did not match any: ",
      inspect(ignore_checks)
    ])

    checks
  end

  defp warn_about_ineffective_patterns({checks, _, _}, _) do
    checks
  end
end
