require 'rainbow/refinement'

module Logging
  using Rainbow

  # Verbosity levels
  QUIET = 0
  NORMAL = 1
  VERBOSE = 2
  DEBUG = 3

  # Class-level instance variables to hold the verbosity setting for the module
  @verbosity = NORMAL

  def self.verbosity
    @verbosity
  end

  def self.verbosity=(level)
    @verbosity = level
  end

  # A thread-safe output method for colored text to STDERR.
  def log_stderr(level, multiline_string, color = nil)
    return unless Logging.verbosity >= level

    multiline_string.to_s.each_line do |line|
      line_to_print = line.chomp
      line_to_print = line_to_print.public_send(color) if color
      warn line_to_print
    end
    $stderr.flush
  end

  # A thread-safe output method for uncolored text to STDOUT.
  def log_stdout(multiline_string)
    $stdout.puts multiline_string.to_s
    $stdout.flush
  end
end
