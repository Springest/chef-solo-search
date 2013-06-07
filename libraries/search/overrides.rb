#
# Copyright 2011, edelight GmbH
#
# Authors:
#       Markus Korn <markus.korn@edelight.de>
#       Seth Chisamore <schisamo@opscode.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

module Search
  module Overrides
    # Overwrite the search method of recipes to operate locally by using
    # data found in data_bags.
    # Only very basic lucene syntax is supported and also sorting the result
    # is not implemented, if this search method does not support a given query
    # an exception is raised.
    # This search() method returns a block iterator or an Array, depending
    # on how this method is called.
    def search(obj, query=nil, sort=nil, start=0, rows=1000, &block)
      if !sort.nil?
        raise "Sorting search results is not supported"
      end
      _query = Query.parse(query)
      if _query.nil?
        raise "Query #{query} is not supported"
      end
      _result = []

      case obj
      when :node
        nodes = search_nodes(_query, start, rows, &block)
        _result += nodes
      when :role
        roles = search_roles(_query, start, rows, &block)
         _result += roles
      else
        bags = search_data_bag(_query, obj, start, rows, &block)
        _result += bags
      end


      if block_given?
        pos = 0
        while (pos >= start and pos < (start + rows) and pos < _result.size)
          yield _result[pos]
          pos += 1
        end
      else
        return _result.slice(start, rows)
      end
    end

    def search_nodes(query, start, rows, &block)
      all_nodes.select { |node| query.match(node.to_hash) }
    end

    def all_nodes
      Dir.glob(File.join(Chef::Config[:data_bag_path], "node", "*.json")).map do |f|
        json = Yajl::Parser.parse(File.read(f))

        if json.has_key?("hostname")
          json["automatic"]  ||= {}
          json["automatic"]["hostname"] = json.delete("hostname")
        end

        node = solo_create_node_from_json(json)

        if node.name.nil?
          node.name(node.hostname)
        end

        node.expand!('disk') # And expand using disk

        node
      end
    end

    def solo_create_node_from_json(o)
      node = Chef::Node.new

      node.name(o["name"])
      node.chef_environment(o["chef_environment"])

      if o.has_key?("attributes")
        node.normal_attrs = o["attributes"]
      end 

      cl = Chef::CookbookLoader.new(Chef::Config[:cookbook_path])
      cl.load_cookbooks

      require "debugger"
      debugger

      node.automatic_attrs = Mash.new(o["automatic"]) if o.has_key?("automatic")
      node.normal_attrs = Mash.new(o["normal"]) if o.has_key?("normal")
      node.default_attrs = Mash.new(o["default"]) if o.has_key?("default")
      node.override_attrs = Mash.new(o["override"]) if o.has_key?("override")

      if o.has_key?("run_list")
        node.run_list.reset!(o["run_list"])
      else
        o["recipes"].each { |r| node.recipes << r } 
      end 

      node
    end

    def search_roles(query, start, rows, &block)
      Dir.glob(File.join(Chef::Config[:role_path], "*.{json,rb}")).collect do |file_name|
        if file_name.end_with?(".json")
          Chef::JSONCompat.from_json(IO.read(file_name))
        elsif file_name.end_with?(".rb")
          Chef::Role.new.tap { |r| r.from_file(file_name) }
        else
          raise "Only .json and .rb are supported!"
        end
      end.select { |role| query.match(role.to_hash) }
    end

    def search_data_bag(_query, bag_name, start, rows, &block)
      _result = []
      data_bag(bag_name.to_s).each do |bag_item_id|
        bag_item = data_bag_item(bag_name.to_s, bag_item_id)
        if _query.match(bag_item)
          _result << bag_item
        end
      end
      return _result
    end
  end
end
