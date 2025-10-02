require_relative '../lib/util/git_tree_walker'
require_relative '../lib/util/thread_pool_manager'

trap('INT') { exit!(-1) }
trap('SIGINT') { exit!(-1) }

begin
  $PROGRAM_NAME = 'commitAll'
  updater = GitUpdater.new(ARGV)
  updater.process
rescue StandardError => e
  puts "An unexpected error occurred: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end
