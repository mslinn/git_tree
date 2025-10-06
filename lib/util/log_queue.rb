require 'singleton'

class LogQueue
  include Singleton

  def initialize
    @queue = Queue.new
    @worker_thread = Thread.new { process_queue }
    @worker_thread.report_on_exception = false # Handled by at_exit
  end

  def log(message)
    @queue.push(message)
  end

  def shutdown
    # Signal the worker to shut down by pushing a special object
    @queue.push(:shutdown)
    # Wait for the worker thread to finish processing all messages
    @worker_thread.join
  end

  private

  def process_queue
    loop do
      message = @queue.pop
      break if message == :shutdown

      write_to_stream(message)
    end

    # Process any remaining messages after the shutdown signal
    # This ensures no messages are lost if they were queued right before shutdown
    until @queue.empty?
      message = @queue.pop
      write_to_stream(message)
    end
  rescue StandardError => e
    # If the logger itself fails, write directly to stderr
    warn "LogQueue worker thread encountered an error: #{e.message}"
  end

  def write_to_stream(message)
    return unless message

    Logging::STDAUX.puts(message)
  end
end
