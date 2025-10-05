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

  # Define a custom I/O stream for auxiliary/informational messages. Defaults to STDERR.
  STDAUX = begin
    IO.for_fd(3, 'w')
  rescue StandardError
    $stderr
  end

  # @return [Integer] The current verbosity level.
  def self.verbosity
    @verbosity
  end

  # @param level [Integer] The new verbosity level.
  # @return [nil]
  def self.verbosity=(level)
    raise ArgumentError, "verbosity level must be an Integer, but got #{level.class}" unless level.is_a?(Integer)

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
    raise ArgumentError, "multiline_string must be a String, but got #{multiline_string.class}" unless multiline_string.is_a?(String)
    raise ArgumentError, "color must be a Symbol or nil, but got #{color.class}" unless color.is_a?(Symbol) || color.nil?
    raise ArgumentError, "log level must be an Integer, but got #{level.class}" unless level.is_a?(Integer)

    return unless Logging.verbosity >= level

    multiline_string.to_s.each_line do |line|
      line_to_print = line.chomp
      line_to_print = line_to_print.public_send(color) if color
      STDAUX.puts line_to_print
    end
    STDAUX.flush
  end

  # A thread-safe output method for uncolored text to STDOUT.
  # @param multiline_string [String] The message to log.
  # @return [nil]
  def log_stdout(multiline_string)
    raise ArgumentError, "multiline_string must be a String, but got #{multiline_string.class}" unless multiline_string.is_a?(String)

    $stdout.puts multiline_string.to_s
    $stdout.flush
  end

  # A thread-safe output method for inline messages to STDERR (no newline).
  # @param level [Integer] The verbosity level of the message.
  # @param message [String] The message to log.
  # @param color [Symbol, nil] The color method to apply from Rainbow.
  # @return [nil]
  def log_inline(level, message, color = nil)
    raise ArgumentError, "message must be a String, but got #{message.class}" unless message.is_a?(String)
    raise ArgumentError, "color must be a Symbol or nil, but got #{color.class}" unless color.is_a?(Symbol) || color.nil?
    raise ArgumentError, "log level must be an Integer, but got #{level.class}" unless level.is_a?(Integer)

    return unless Logging.verbosity >= level

    message = message.public_send(color) if color
    STDAUX.print message
  end

  # Make log and log_stdout available as both instance and module methods
  module_function :log, :log_stdout, :log_inline
end
