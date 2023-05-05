module MslinnUtil
  # Return the longest path prefix that is a prefix of all paths in array.
  # If array is empty, return the empty string ('').
  def self.common_prefix(paths, allow_root_match: false)
    return '' if paths.empty?

    return paths.first.split('/').slice(0...-1).join('/') if paths.length <= 1

    arr = paths.sort
    first = arr.first.split('/')
    last = arr.last.split('/')
    i = 0
    i += 1 while first[i] == last[i] && i <= first.length
    result = first.slice(0, i).join('/')

    result.empty? && allow_root_match ? '/' : result
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
