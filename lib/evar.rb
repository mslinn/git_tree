class Evar
  attr_accessor :children, :name, :short_value, :full_value, :parent

  def initialize(name, value, parent = nil)
    @name = name
    @children = []
    @full_value = value
    @parent = parent
  end

  def add_child(child)
    @children << child
    self
  end

  def basename
    File.basename @full_value
  end

  def dirname
    File.dirname @full_value
  end

  def last_subdirectory
    File.dirname File.dirname @full_value
  end

  def level
    @full_value.count '/'
  end

  def short_dirname
    File.dirname @short_value
  end

  def to_s
    "export @name=" + @short_value ? @short_value : @full_value
  end
end

class Evars
  attr_accessor :root

  def initialize(root, allow_root_match: false)
    @root = root
    @allow_root_match = allow_root_match
    @evars = [] # all evars
    @nodes = [] # array of lists of nodes
  end

  def add(evar)
    @evars << evar
  end

  # Group evars by their number of nodes.
  # Store groups into an array of lists of evars.
  def group_nodes
    @nodes = []
    @evars.each { |evar| @nodes[evar.level] << evar }
  end

  # TODO: make this more useful
  # Generates output (export statements)
  def list
    puts @evars.join("\n") + "\n"
  end

  def process_node(level)
    level_nodes = @evars[level]
    roots = MslinnUtil.roots(level_nodes, level)
    level_nodes.each do |node|
      root = roots.find { |r| node.full_value.start_with? r }
      root_name = root.count '/'
      node.short_value = node.full_value.tr(root, '$' + root_name)
    end
  end

  def unique_sibling_prefixes(level)
    @evars[level].select(&:leaf_subdirectory)
  end

  def process_nodes
    # @evars[0] is empty if !allow_root_match, else only contains node for '/'
    @evars[1].each do |node|
      unique_sibling_names(1).find
    end
  end
end
