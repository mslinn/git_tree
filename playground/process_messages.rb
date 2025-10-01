WORKER_COUNT = 3
JOBS_TO_CREATE = 10
SHUTDOWN_SIGNAL = :shutdown

# --- Shared State Start ---
# The main queue where the producer sends work.
@main_work_queue = Queue.new

# An array to hold our worker threads and their individual queues.
@workers = []
# --- Shared State End ---

# This method is the producer tha runs on main thread;
# it creates jobs and sends them to the monitor thread.
def create_jobs(jobs_to_create)
  puts "[Producer] Creating #{jobs_to_create} jobs..."
  JOBS_TO_CREATE.times { |i| @main_work_queue.push("Job ##{i}") }
  @main_work_queue.push(SHUTDOWN_SIGNAL) # Signal that production is complete.
end

# Creates a monitor thread that manages the thread pool.
# It takes jobs from the work queue and dispatches them to worker threads.
def create_monitor(worker_count)
  Thread.new do
    puts "[Monitor] Ready to dispatch work."
    worker_index = 0
    loop do
      # The monitor blocks here, waiting for the producer to send a job.
      job = @main_work_queue.pop
      break if job == SHUTDOWN_SIGNAL

      # Distribute the job to the next worker in a round-robin fashion.
      target_worker = @workers[worker_index]
      puts "[Monitor] Dispatching '#{job}' to Worker #{worker_index}."
      target_worker[:queue].push(job)

      # Move to the next worker for the next job.
      worker_index = (worker_index + 1) % worker_count
    end

    puts "[Monitor] Received shutdown signal. Relaying to all @workers..."
    @workers.each do |worker|
      worker[:queue].push(SHUTDOWN_SIGNAL)
      worker[:thread].join # Wait for all @workers to finish.
    end
    puts "[Monitor] All @workers have shut down. Monitor finished."
  end
end

def initialize_workers(worker_count)
  puts "Initializing #{worker_count} worker threads..."
  worker_count.times do |i|
    # Each worker gets its own personal queue. The monitor will push work here.
    worker_queue = Queue.new
    worker_thread = Thread.new do
      loop do
        job = worker_queue.pop # The worker blocks here, waiting for the monitor to give it a job.
        break if job == SHUTDOWN_SIGNAL

        puts "  [Worker #{i}] Processing job: '#{job}'"
        sleep(rand(1..3)) # Simulate doing work
        puts "  [Worker #{i}] Finished job: '#{job}'"
      end
      puts "  [Worker #{i}] Shutting down."
    end
    @workers << { thread: worker_thread, queue: worker_queue }
  end
end

initialize_workers WORKER_COUNT
monitor = create_monitor(WORKER_COUNT)
create_jobs JOBS_TO_CREATE
monitor.join # Wait for the monitor to finish (which in turn waits for all @workers).
puts "\nAll work is complete."
