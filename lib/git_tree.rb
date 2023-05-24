module GitTree
  require 'find'
  require 'rugged'
  require_relative 'util'

  # @return array containing directory names to process
  #   Each directory name ends with a slash, to ensure symlinks are dereferences
  def self.directories_to_process(root)
    root_fq = File.expand_path root
    abort "Error: #{root_fq} is a file, instead of a directory. Cannot recurse." if File.file? root_fq

    root_fq = MslinnUtil.deref_symlink(root_fq).to_s
    abort "Error: #{root_fq} does not exist. Halting." unless Dir.exist? root_fq

    result = []
    Find.find(root_fq) do |path|
      next if File.file? path

      Find.prune if File.exist?("#{path}/.ignore")

      if Dir.exist?("#{path}/.git")
        result << path.to_s
        Find.prune
      end
    end
    result.map { |x| x.delete_prefix("#{root_fq}/") }
  end
end
