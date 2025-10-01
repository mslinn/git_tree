require 'etc'
require 'rainbow/refinement'

# A simple thread pool manager.
class ThreadPool
  using Rainbow

  SHUTDOWN_SIGNAL = :shutdown

  # Calculate the number of worker threads as 75% of available processors
  # (less one for the monitor thread), with a minimum of 1.
  def initialize(percent_available_processors = 0.75)
    if percent_available_processors > 1 || percent_available_processors <= 0
      msg = <<~END_MSG
        Error: The allowable range for the ThreadPool.initialize percent_available_processors is between 0 and 1.
        You provided #{percent_available_processors}.
      END_MSG
      output msg, color: :red
      exit! 1
    end
    @worker_count = [((Etc.nprocessors - 1) * percent_available_processors).floor, 1].max
    @main_work_queue = Queue.new
    @workers = []
  end

  # This method is the producer; it creates tasks and sends them to the monitor thread.
  def create_tasks(tasks)
    output "[Producer] Creating #{tasks.count} tasks..."
    tasks.each { |task| @main_work_queue.push(task) }
    @main_work_queue.push(SHUTDOWN_SIGNAL) # Signal that production is complete.
  end

  def max_worker_count
    @worker_count
  end

  # A thread-safe output method.
  def output(message, color = nil)
    message.each_line do |line|
      line_to_print = line.chomp
      line_to_print = line_to_print.public_send(color) if color
      $stdout.puts line_to_print
    end
    $stdout.flush
  end

  # Starts the workers and the monitor, then waits for everything to complete.
  # It accepts a block that defines what work each worker will perform.
  def run(&)
    initialize_workers(&)
    monitor = create_monitor

    # Wait for the monitor to finish (which in turn waits for all workers).
    monitor.join
    output "\nAll work is complete.", :green
  end

  private

  # Creates a monitor thread that manages the thread pool.
  # It takes tasks from the work queue and dispatches them to worker threads.
  def create_monitor
    Thread.new do
      output "[Monitor] Ready to dispatch work."
      worker_index = 0
      loop do
        # The monitor blocks here, waiting for the producer to send a task.
        task = @main_work_queue.pop
        break if task == SHUTDOWN_SIGNAL

        # Distribute the task to the next worker in a round-robin fashion.
        target_worker = @workers[worker_index]
        output "[Monitor] Dispatching '#{task}' to Worker #{worker_index}."
        target_worker[:queue].push(task)

        # Move to the next worker for the next task.
        worker_index = (worker_index + 1) % @worker_count
      end

      output "[Monitor] Received shutdown signal. Relaying to all workers...", :yellow
      # Wait for all workers to finish.
      @workers.each do |worker|
        worker[:queue].push(SHUTDOWN_SIGNAL)
        worker[:thread].join
      end
      output "[Monitor] All workers have shut down. Monitor finished.", :yellow
    end
  end

  def initialize_workers
    output "Initializing #{@worker_count} worker threads..."
    @worker_count.times do |i|
      worker_queue = Queue.new
      worker_thread = Thread.new do
        loop do
          task = worker_queue.pop # The worker blocks here, waiting for the monitor to give it a task.
          break if task == SHUTDOWN_SIGNAL

          yield(self, task, i) # Execute the provided block of work.
        end
        output "  [Worker #{i}] Shutting down.", :cyan
      end
      @workers << { thread: worker_thread, queue: worker_queue }
    end
  end
end
