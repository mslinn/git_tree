require_relative '../lib/util/thread_pool_manager'

pool = ThreadPool.new
num_tasks = (pool.max_worker_count * 3.5).to_i # Ensure there are many more tasks than worker threads
tasks = (1..num_tasks).map { |i| "Task ##{i}" }
pool.create_tasks(tasks)
pool.run do |p, task, worker_id|
  p.output "  [Worker #{worker_id}] Starting task: '#{task}'", :blue
  sleep(rand(1..3)) # Simulate doing work
  p.output "  [Worker #{worker_id}] Finished task: '#{task}'", :blue
end
