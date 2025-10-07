require 'open3'

class CommandRunner
  # Executes a shell command in a specified directory, capturing stdout and stderr output streams, plus status.
  #
  # This wrapper simplifies running external commands (e.g., git) with directory context,
  # making it easy to mock in tests. It uses +Open3.capture3+ to separately capture stdout
  # and stderr for granular handling (e.g., logging errors distinctly). Unlike +Open3.capture2e+
  # (which merges streams, potentially interleaving output), this avoids parsing issues in
  # complex commands.
  #
  # Validates inputs strictly. Caller must check +status.exitstatus+ for success (non-zero
  # indicates failure). If +raise_on_error+ is +true+, raises +SystemCallError+ on failure.
  #
  # @param command [String] The shell command to execute (e.g., "git status").
  # @param dir [String] The working directory to +chdir+ into before execution.
  # @param raise_on_error [Boolean] If +true+, raise on non-zero exit status (default: +false+).
  # @return [Array] A 3-element tuple: +[stdout, stderr, status]+, where:
  #   - +stdout+ is a +String+ of standard output.
  #   - +stderr+ is a +String+ of standard error.
  #   - +status+ is a +Process::Status+ object.
  # @raise [ArgumentError] If +command+ or +dir+ is unspecified (+nil+).
  # @raise [TypeError] If +command+ or +dir+ is not a +String+.
  # @raise [SystemCallError] If +raise_on_error+ is +true+ and the command fails (non-zero exit).
  # @example
  #   # Basic capture (check status manually)
  #   stdout, stderr, status = run("git status", "/path/to/repo")
  #   if status.success?
  #     puts "Output: #{stdout}"
  #   else
  #     puts "Error: #{stderr}"
  #   end
  #   # => ["On branch main\n", "", #<Process::Status: ...>]
  #
  #   # With auto-raise
  #   run("git invalid", "/path/to/repo", raise_on_error: true)
  #   # Raises SystemCallError if 'git invalid' fails
  #
  #   # In tests (mockable)
  #   allow_any_instance_of(CommandRunner).to receive(:run).and_return(["mocked out", "mocked err", double("status", success?: true)])
  def run(command, dir, raise_on_error: false)
    raise ArgumentError, 'command was not specified' unless command
    raise ArgumentError, 'dir was not specified' unless dir
    raise TypeError, "command must be a String, but got #{command.class}" unless command.is_a?(String)
    raise TypeError, "dir must be a String, but got #{dir.class}" unless dir.is_a?(String)

    stdout, stderr, status = Open3.capture3(command, chdir: dir)
    raise SystemCallError.new(status.exitstatus, command) if raise_on_error && !status.success?

    [stdout, stderr, status]
  end
end
