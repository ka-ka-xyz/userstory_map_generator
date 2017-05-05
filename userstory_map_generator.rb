# coding: utf-8
require 'gviz'
require 'pp'
require 'yaml'
require 'rdoc'
require 'rubytree'
require 'os'
require 'zlib'

input_filename = ARGV[0] ? ARGV[0] : "input.usl"
output_filename = ARGV[1] ? ARGV[1] : "output"
conf = YAML.load_file(File.join(__dir__, 'conf.yaml'))

data = File.read(input_filename)

def parse(markup, tree = nil, level=0, isListChild = false)
  level = isListChild ? level + 1 : level
  case markup
  when RDoc::Markup::Paragraph then
    tree.rename(markup.text)
    tree.content = {level: level}
  when RDoc::Markup::List then
    if markup.type == "BULLET".to_sym ||
        markup.type == "NUMBER".to_sym ||
        markup.type == "UALPHA".to_sym then
      markup.items.each do |e|
        parse(e, tree.add(Tree::TreeNode.new('')), level, true)
      end
    end
  when RDoc::Markup::ListItem then
    markup.parts.each do |e|
      parse(e, tree, level)
    end
  when RDoc::Markup::Document then
    markup.parts.each do |e|
      parse(e, tree, level)
    end
  when RDoc::Markup::Heading then
    if tree.is_root? then
      tree.rename(markup.text)
    end
  end
end

tree = Tree::TreeNode.new("ROOT")
parse(RDoc::Markdown.parse(data), tree)
#pp usml.backbones.map{|e| {e.text.to_sym => e}}
#tree.print_tree

opts_ = {}
if OS.windows? then
  # graphviz require fontname when exec on windows.
  opts_ = opts_.merge(conf["win_opt"])
end
if conf["font_opt"] then
  opts_ = opts_.merge(conf["font_opt"])
end

def gen_id(tree_node)
  Zlib::crc32(tree_node.name).to_s.to_sym
end
def gen_subgraph_id(tree_node)
  "sub_#{gen_id(tree_node)}".to_sym
end

def bold_first_line(str)
  stars = str.split(/\R/)
  first = stars.shift
  first = "<U><B>#{first}</B></U>"
  "#{stars.unshift(first).join('<BR/>')}<BR/>"
end

Graph do
  global opts_.merge(label: bold_first_line(tree.root.name))
  tree.each do |tree_node|
    opts = opts_
    if tree_node.is_root? then
      next
    end
    level = tree_node.content[:level]
    #opts = opts.merge({rank: level})
    case level
    when 1 then
      subgraph do
        global conf["backbone_subgraph_opt"]
        node gen_id(tree_node), {label: bold_first_line(tree_node.name)}.merge(opts).merge(conf["backbone_opts"])
        tree_node.children.each do |c1|
          subgraph do
            global conf["narrativeflow_subgraph_opt"]
            node gen_id(c1), {label: bold_first_line(c1.name)}.merge(opts).merge(conf["narrativeflow_opts"])
            subgraph do
              global conf["detail_subgroup_opt"].merge({rank:"same"})

              # ugly hitfix to display level3 node in collect order
              c1.children.reverse.each do |c2|
                if c1 != c2 then
                  node gen_id(c2), {label: bold_first_line(c2.name)}.merge(opts).merge(conf["details_opts"])
                end
              end

              c1.each do |c2|
                if c1 != c2 && c2.content[:level] > 3 then
                  node gen_id(c2), {label: bold_first_line(c2.name)}.merge(opts).merge(conf["details_opts"])
                end
              end
            end
          end
        end
      end
    end

    if !tree_node.children.empty? then
      route gen_id(tree_node) => tree_node.children.map{|c| gen_id(c)}
      tree_node.children.each do |c|
        edge "#{gen_id(tree_node)}_#{gen_id(c)}".to_sym, conf["edge_opts"]
      end
    end
  end

  tree.root.children.each do |backbone|
    if backbone.next_sibling then
      edge "#{gen_id(backbone)}_#{gen_id(backbone.next_sibling)}", conf["backbone_edge_opts"]
    end
  end
  save(output_filename.to_sym, :png)
end
