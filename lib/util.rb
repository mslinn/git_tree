module MslinnUtil
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
