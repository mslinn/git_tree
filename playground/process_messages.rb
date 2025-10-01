require_relative '../lib/util/thread_pool_manager'

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
