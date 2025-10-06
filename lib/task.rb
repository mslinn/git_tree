require_relative 'util/command_runner'

# Open3.capture3 result is captured in this structure
ExecResult = Struct('ExecResult', :stdio, :stderr, :status)

# Most recent program execution is remembered in this structure
Execution = Struct('Execution', :command, :dir, :exec_result, :error) do
  def include?(text)
    exec_result.stdio.include?(text) ||
      exec_result.stderr.include?(text)
  end
end

# Messages sent to user by this task (stdaux)
UserMessage = Struct('UserMessage', :message, :color)

# Remembers all commands that were executed by this task, and the results
# Also remembers user output
class Task
  attr_reader :history

  def initialize
    @history = [] # Array<UserMessage|Execution>
  end

  # @return most recent UserMessage in @history
  def most_recent_user_message
    @history.reverse.find { |item| item.is_a?(UserMessage) }
  end

  # @return most recent Execution in @history
  def exec_result_execution
    @history.reverse.find { |item| item.is_a?(Execution) }
  end

  # @param message [String] multiline string is only included in history if verbosity makes it visible
  def message_user(log_level, message, color)
    return if Logging.verbosity < log_level

    Logging.log log_level, message, color
    @history << UserMessage.new(message, color)
  end

  def perform(command, dir)
    execution = Execution.new(command, dir)
    begin
      execution.exec_result = CommandRunner.run command, dir
    rescue StandardError => e
      execution.error = e
    end
    @history << execution
  end

  def repo(dir) = Rugged::Repository.init_at(dir)
end
