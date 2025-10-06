require 'open3'

class CommandRunner
  # Executes a shell command in a specified directory.
  # This is wrapped in a class to make it easy to mock in tests.
  # @param command [String] The shell command to execute.
  # @param dir [String] The directory to execute the command in.
  # @return [Array] A tuple containing the output and the status object.
  def run(command, dir)
    raise TypeError, "command must be a String, but got #{command.class}" unless command.is_a?(String)
    raise TypeError, "dir must be a String, but got #{dir.class}" unless dir.is_a?(String)

    # Why is Open3.capture2e used instead of Open3.capture3?
    Open3.capture2e(command, chdir: dir)
  end
end
