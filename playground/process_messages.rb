require_relative '../lib/util/thread_pool_manager'

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

def dispatch_work(task_input_messages, &)
  pool = FixedThreadPoolManager.new
  pool.create_tasks_from(task_input_messages)
  pool.run(&)
end

# This writing style is better for unit testing
task_input_messages = (1..42).map { |i| "Input for task ##{i}" }
test_proc = proc do |worker, task, worker_id|
  worker.output "  [Worker #{worker_id}] Starting task: '#{task}'", :magenta
  sleep(rand(0..2)) # Simulate doing work
  worker.output "  [Worker #{worker_id}] Finished task: '#{task}'", :magenta
end
dispatch_work task_input_messages, &test_proc

puts "\n--- More compressed writing style; Running dispatch_work with a block ---"
dispatch_work((1..20)
  .map { |i| "Block task ##{i}" }) do |worker, task, worker_id|
  worker.output "  [Worker #{worker_id}] Starting task: '#{task}'", :cyan
  sleep(rand(0..1)) # Simulate doing work
  worker.output "  [Worker #{worker_id}] Finished task: '#{task}'", :cyan
end
