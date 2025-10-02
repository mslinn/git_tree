require_relative '../lib/util/thread_pool_manager'

# Running this program should yield messages cycling through a rainbow of cool colors
# with other colors occassionally making an appearance.

# This example mixes test data and infrastructure
# Just to show all the moving parts
# The next examples use FixedThreadPoolManager.dispatch_work which simplifies the following code:
def test1
  pool = FixedThreadPoolManager.new
  # Ensure there are many more tasks than worker threads for this test
  num_tasks = (pool.max_worker_count * 3.5).to_i
  task_input_messages = (1..num_tasks).map { |i| "Input message for task ##{i}" }
  pool.create_tasks_from task_input_messages
  pool.run do |worker, task, worker_id|
    worker.output "  [Worker #{worker_id}] Starting task: '#{task}'", :blue
    sleep(rand(0..2)) # Simulate doing work
    worker.output "  [Worker #{worker_id}] Finished task: '#{task}'", :blue
  end
end

# Write your code this way if all the data is available at once.
# This writing style separates the creation of input data (task_input_messages)
# from the creation of the thread pool and the processing of the data.
# This is also a good construct for unit testing.
def test_data_array
  task_input_messages = (1..12).map { |i| "Input message for task ##{i}" }
  test_proc = proc do |worker, task, worker_id|
    worker.output "  [Worker #{worker_id}] Starting task: '#{task}'", :magenta
    sleep(rand(0..2)) # Simulate doing work
    worker.output "  [Worker #{worker_id}] Finished task: '#{task}'", :magenta
  end
  FixedThreadPoolManager.dispatch_work task_input_messages, &test_proc
end

# Do not write your code this way if all the data is available at once.
# This more compressed writing style is relatively expensive to maintain
# Yes, it seems like someone intelligent wrote this code.
# Bubble burst: I am the author and I know that I am not that smart.
def test_bad
  puts "\n--- Running dispatch_work with a block ---"
  FixedThreadPoolManager.dispatch_work((1..12).map { |i| "Block task input message ##{i}" }) do |worker, task, worker_id|
    worker.output "  [Worker #{worker_id}] Starting task: '#{task}'", :cyan
    sleep(rand(0..2)) # Simulate doing work
    worker.output "  [Worker #{worker_id}] Finished task: '#{task}'", :cyan
  end
end

# This demonstrates how to use FixedThreadPoolManager when messages are available at different times
def test_data_drip(message_count: 10)
  puts "\n--- Running test_data_drip with #{message_count} tasks---", :green
  pool = FixedThreadPoolManager.new

  # Start the pool and provide the block of work for the workers
  # Although the block encloses the current context, so pool.output can be used,
  # worker provides a related context
  pool.start do |worker, task, worker_id|
    worker.output "  [Worker #{worker_id}] Starting task: '#{task}'", :green
    sleep(rand(1..3)) # Simulate doing work
    worker.output "  [Worker #{worker_id}] Finished task: '#{task}'", :green
  end

  # Drip-feed tasks into the pool over time
  # The block encloses the current context, so pool.output can be used
  message_count.times do |i|
    task_message = "Drip-fed task ##{i + 1}", :green
    pool.output "[Producer] Adding new task: '#{task_message}'", :green
    pool.add_task(task_message)
    sleep(rand(0..1)) # Generate each task at a diffent time
  end

  pool.output '[Producer] All tasks have been added. Signalling pool shutdown.', :green
  pool.shutdown # Signal shutdown (non-blocking)
  pool.output '[Producer] Cleaning up main program.', :green
  # Peform any other cleanup operations for the program here
  pool.output '[Producer] Waiting for all threads to complete.', :green
  pool.wait_for_completion # Block and wait for a graceful exit
  pool.output "Program finished gracefully.", :green
end

test_data_drip(message_count: 50)
