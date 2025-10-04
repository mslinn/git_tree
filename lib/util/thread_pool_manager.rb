require 'etc'
require_relative 'log'

class FixedThreadPoolManager
  include Logging

  SHUTDOWN_SIGNAL = :shutdown

  # Calculate the number of worker threads as 75% of available processors
  # (less one for the monitor thread), with a minimum of 1.
  # @param percent_available_processors [Float] The percentage of available processors to use for worker threads.
  def initialize(percent_available_processors = 0.75)
    if percent_available_processors > 1 || percent_available_processors <= 0
      msg = <<~END_MSG
        Error: The allowable range for the ThreadPool.initialize percent_available_processors is between 0 and 1.
        You provided #{percent_available_processors}.
      END_MSG
      log QUIET, msg, :red
      exit! 1
    end
    @worker_count = [(Etc.nprocessors * percent_available_processors).floor, 1].max
    @main_work_queue = Queue.new
    @workers = []
  end

  # Adds a single task to the work queue.
  # The pool must have been started with `start` first.
  def add_task(task)
    @main_work_queue.push(task)
  end

  # Signals the pool to shut down after all currently queued tasks are processed.
  # This is a non-blocking method.
  # When you call it, it simply places a special SHUTDOWN_SIGNAL message onto the
  # main work queue. The method returns immediately, allowing your main thread to
  # continue with other tasks.
  # It's like telling the pool, "I'm not going to give you any more tasks,
  # so start wrapping things up when you're done with what you have."
  def shutdown
    @main_work_queue.push(SHUTDOWN_SIGNAL)
  end

  # Starts the workers and the monitor, but does not wait for them to complete.
  # This is for "drip-feeding" tasks.
  # @param Block of code to execute for each task.
  # @return nil
  def start(&)
    initialize_workers(&)
  end

  # This is the last method to call when using FixedPoolManager.
  # This is a blocking method.
  # It pauses the execution of your main thread and waits until the monitor and all worker threads have
  # fully completed their work and terminated.
  def wait_for_completion
    @worker_count.times { @main_work_queue.push(SHUTDOWN_SIGNAL) }

    last_active_count = -1
    loop do
      active_workers = @workers.count(&:alive?)
      break if active_workers.zero?

      if active_workers != last_active_count
        warn format("Waiting for %d worker threads to complete...", active_workers) + "\r" if Logging.verbosity > NORMAL
        last_active_count = active_workers
      end
      begin
        sleep 0.1
      rescue Interrupt
        # This can be interrupted by Ctrl-C. We catch it here to allow the main thread's
        # rescue block to handle the exit gracefully without a stack trace.
      end
    end

    warn (" " * 60) + "\r" # Clear the line
    log NORMAL, "All work is complete.", :green
  end

  private

  def initialize_workers
    log NORMAL, "Initializing #{@worker_count} worker threads...", :green
    @worker_count.times do |i|
      worker_thread = Thread.new do
        log NORMAL, "  [Worker #{i}] Started.", :cyan
        start_time = Time.now
        start_cpu = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
        tasks_processed = 0

        loop do
          task = @main_work_queue.pop # The worker blocks here, waiting for a task.
          break if task == SHUTDOWN_SIGNAL

          yield(self, task, i) # Execute the provided block of work.
          tasks_processed += 1
        end

        elapsed_time = Time.now - start_time
        cpu_time = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID) - start_cpu
        shutdown_msg = format(
          "  [Worker #{i}] Shutting down. Processed #{tasks_processed} tasks. Elapsed: %.2fs, CPU: %.2fs",
          elapsed_time, cpu_time
        )
        log NORMAL, shutdown_msg, :cyan
      rescue Interrupt
        # This thread was interrupted by Ctrl-C, likely while waiting on the queue.
        # Exit gracefully without a stack trace.
      end
      # Suppress automatic error reporting for this thread. The error should be handled elsewhere.
      worker_thread.report_on_exception = false
      @workers << worker_thread
    end
  end
end
