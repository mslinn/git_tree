require 'rainbow/refinement'

module Logging
  using Rainbow

  # Verbosity levels
  QUIET = 0
  NORMAL = 1
  VERBOSE = 2
  DEBUG = 3

  # A thread-safe output method for colored text to STDERR.
  def log_stderr(multiline_string, color = nil)
    multiline_string.each_line do |line|
      line_to_print = line.chomp
      line_to_print = line_to_print.public_send(color) if color
      warn line_to_print
    end
    $stderr.flush
  end

  # A thread-safe output method for uncolored text to STDOUT.
  def log_stdout(multiline_string)
    $stdout.puts multiline_string
    $stdout.flush
  end

  def log(level, msg)
    warn msg if @verbosity >= level
  end
end
