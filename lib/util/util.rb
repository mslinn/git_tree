module MslinnUtil
  # @param paths [Array[String]] all start with a leading '/' (they are assumed to be absolute paths).
  # @return [String] the longest path prefix that is a prefix of all paths in array.
  #   If array is empty, return ''.
  #   If only the leading slash matches, and allow_root_match is true, return '/', else return ''.
  def self.common_prefix(paths, allow_root_match: false)
    return '' if paths.empty?

    relative_paths = paths.reject { |x| x.start_with? '/' }
    abort "Error: common_prefix received relative paths:" + relative_paths.map { |x| "  #{x}\n" } \
      unless relative_paths.empty?

    if paths.length == 1
      result = paths.first.split('/').slice(0...-1).join('/')
      return result.empty? && allow_root_match ? '/' : result
    end

    arr = paths.sort
    first = arr.first.split('/')
    last = arr.last.split('/')
    i = 0
    i += 1 while first[i] == last[i] && i <= first.length
    result = first.slice(0, i).join('/')

    result.empty? && allow_root_match ? '/' : result
  end

  # @param paths [Array[String]] absolute paths to examine
  # @param level [Int] minimum # of leading directory names in result, origin 1
  def self.roots(paths, level, allow_root_match: false)
    abort "Error: level must be positive, but it is #{level}." unless level.positive?
    return allow_root_match ? '/' : '' if paths.empty?

    abort("Error: level parameter must be positive, #{level} was supplied instead.") if level <= 0

    if paths.length == 1
      root = File.dirname(paths.first)
      return allow_root_match ? '/' : '' if root == '/'

      return root
    end

    loop do
      paths = trim_to_level(paths, level) # does this change paths in the caller?
      return paths.first if paths.length == 1

      level -= 1
      break if level.zero?
    end

    allow_root_match ? '/' : ''
  end

  # @param paths [Array[String]] absolute paths to examine
  # @param level is origin 1
  def self.trim_to_level(paths, level)
    result = paths.map do |x|
      elements = x.split('/').reject(&:empty?)
      '/' + elements[0..level - 1].join('/')
    end
    result.sort.uniq
  end

  # @return Path to symlink
  def self.deref_symlink(symlink)
    require 'pathname'
    Pathname.new(symlink).realpath
  end

  def self.ensure_ends_with(string, suffix)
    string = string.delete_suffix suffix
    "#{string}#{suffix}"
  end

  def self.expand_env(str)
    str.gsub(/\$([a-zA-Z_][a-zA-Z0-9_]*)|\${\g<1>}|%\g<1>%/) do
      ENV.fetch(Regexp.last_match(1), nil)
    end
  end
end
