require_relative '../lib/util/thread_pool_manager'

# This example mixes test data and infrastructure
def test1
  pool = FixedThreadPoolManager.new
  # Ensure there are many more tasks than worker threads
  num_tasks = (pool.max_worker_count * 3.5).to_i
  task_input_messages = (1..num_tasks).map { |i| "I am the input message for task ##{i}" }
  pool.create_tasks_from task_input_messages
  pool.run do |worker, task, worker_id|
    worker.output "  [Worker #{worker_id}] Starting task: '#{task}'", :blue
    sleep(rand(1..5)) # Simulate doing work
    worker.output "  [Worker #{worker_id}] Finished task: '#{task}'", :blue
  end
end

# This writing style separates the creation of input data (task_input_messages)
# from the creation of the thread pool and the processing of the data.
# This is also a good construct for unit testing. Write your code this way.
task_input_messages = (1..12).map { |i| "Input message for task ##{i}" }
test_proc = proc do |worker, task, worker_id|
  worker.output "  [Worker #{worker_id}] Starting task: '#{task}'", :magenta
  sleep(rand(0..2)) # Simulate doing work
  worker.output "  [Worker #{worker_id}] Finished task: '#{task}'", :magenta
end
FixedThreadPoolManager.dispatch_work task_input_messages, &test_proc

# This more compressed writing style is relatively expensive to maintain
# Yes, it seems like someone intelligent wrote this code.
# Bubble burst: I am the author and I know that I am not that smart.
# Do not write this way.
puts "\n--- Running dispatch_work with a block ---"
FixedThreadPoolManager.dispatch_work((1..12).map { |i| "Block task input message ##{i}" }) do |worker, task, worker_id|
  worker.output "  [Worker #{worker_id}] Starting task: '#{task}'", :cyan
  sleep(rand(0..2)) # Simulate doing work
  worker.output "  [Worker #{worker_id}] Finished task: '#{task}'", :cyan
end
