require 'rainbow/refinement'

module Logging
  using Rainbow

  # Verbosity levels
  QUIET   = 0
  NORMAL  = 1
  VERBOSE = 2
  DEBUG   = 3

  # Class-level instance variables to hold the verbosity setting for the module
  @verbosity = ::Logging::NORMAL
  # warn "Logging module loaded. Default verbosity: #{@verbosity}" if @verbosity >= NORMAL

  # @return [Integer] The current verbosity level.
  def self.verbosity
    @verbosity
  end

  # @param level [Integer] The new verbosity level.
  # @return [nil]
  def self.verbosity=(level)
    # warn "Logging.verbosity= called. Changing from #{@verbosity} to #{level}" \
    #   if (@verbosity || NORMAL) >= NORMAL ||
    #      (level || NORMAL) >= NORMAL
    @verbosity = level
  end

  # A thread-safe output method for colored text to STDERR.
  # @param level [Integer] The verbosity level of the message.
  # @param multiline_string [String] The message to log.
  # @param color [Symbol, nil] The color method to apply from Rainbow, e.g., :red, :green.  If nil, no color is applied.
  # @return [nil]
  def log(level, multiline_string, color = nil)
    return unless Logging.verbosity >= level

    multiline_string.to_s.each_line do |line|
      line_to_print = line.chomp
      line_to_print = line_to_print.public_send(color) if color
      warn line_to_print
    end
    $stderr.flush
  end

  # A thread-safe output method for uncolored text to STDOUT.
  # @param multiline_string [String] The message to log.
  # @return [nil]
  def log_stdout(multiline_string)
    $stdout.puts multiline_string.to_s
    $stdout.flush
  end
end
