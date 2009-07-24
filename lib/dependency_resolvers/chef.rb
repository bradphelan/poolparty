=begin rdoc
Base dependency_resolver
=end
module DependencyResolvers
  
  class Chef < Base
    
    class << self
      attr_reader :cookbook_directory
      
      def before_compile
        @cookbook_directory = compile_directory/"cookbooks"/"poolparty"
        require_chef_only_resources
        raise PoolParty::PoolPartyError.create("ChefCompileError", "No compile_directory is specified. Please specify one.") unless compile_directory
        FileUtils.mkdir_p cookbook_directory unless ::File.directory?(cookbook_directory)
      end
      
      def after_compile(o)
        compile_default_recipe(o)
        compile_variables
        compile_files
        compile_recipes
        
        write_dna_json
        write_solo_dot_rb
      end
         
      # compile the resources
      # Compiles the resource appropriately against the type
      # If the resource is a variable, then we don't have any output
      # as the output will be handled in after_compile with compile_variables
      # If the resource is a file, then add it to the files array and run the
      # compile_resource command (on super) for the output. The file will later
      # be turned into a .erb template file in the compile_directory
      # Otherwise just run the output to get the default.rb recipe
      def compile_resource(res)
        # Apply meta_functions here
        o = case res
        when PoolParty::Resources::Variable
          # do variable stuff
          variables << res
          ""
        when PoolParty::Resources::FileResource
          files << res
          super
        else
          super
        end
        
        apply_meta_functions(res, o)
      end
      
      default_attr_reader :variables, []
      default_attr_reader :files, []
      
      private
      
      def require_chef_only_resources
        # Require the chef-only resources
        $:.unshift("#{File.dirname(__FILE__)}/chef")

        %w( http_request remote_directory remote_file 
            route script).each do |res|
          require "resources/#{res}"
        end
      end
      
      # Take this string and apply metafunctions to the string on the resource
      # If there are no meta functions on the resource, do not touch the resulting
      # string
      def apply_meta_functions(re, str)
        regex = /[(.*)do(\w*)?(.*)]?[\w+]*end$/
        
        add = []
        add << "  notifies :#{re.meta_notifies[0]}, resources(:#{re.meta_notifies[1].has_method_name} => \"#{re.meta_notifies[1].name}\")" if re.meta_notifies
        add << "  subscribes :#{re.meta_subscribes[0]}, resources(:#{re.meta_subscribes[1].has_method_name} => \"#{re.meta_subscribes[1].name}\"), :#{re.meta_subscribes[2]}" if re.meta_subscribes

        if re.meta_not_if
          tmp = "not_if "
          tmp += re.meta_not_if[1] == :block ? "do #{re.meta_not_if[0]} end" : "\"#{re.meta_not_if[0]}\""
          add << tmp
        end
        
        if re.meta_only_if
          tmp = "only_if "
          tmp += re.meta_only_if[1] == :block ? "do #{re.meta_only_if[0]} end" : "\"#{re.meta_only_if[0]}\""
          add << tmp
        end

        add << "  ignore_failure #{re.print_variable(re.ignore_failure)}" if re.ignore_failure
        add << "  provider #{re.print_variable(re.provider)}" if re.provider
        
        return str if add.empty?
        newstr = str.chomp.gsub(regex, "\0")
        "#{newstr}#{add.join("\n")}\nend"
      end
      
      # Take the variables and compile them into the file attributes/poolparty.rb
      def compile_variables
        FileUtils.mkdir_p cookbook_directory/"attributes" unless ::File.directory?(cookbook_directory/"attributes")
        File.open(cookbook_directory/"attributes"/"poolparty.rb", "w") do |f|
          f << "# PoolParty variables\n"
          f << "poolparty Mash.new unless attribute?('poolparty')\n"
          variables.each do |var|
            f << "poolparty[:#{var.name}] = #{handle_print_variable(var.value)}\n"
          end
        end
      end
      
      # Compile the files
      def compile_files
        FileUtils.mkdir_p cookbook_directory/"files" unless ::File.directory?(cookbook_directory/"files")
        files.each do |fi|
          fpath = cookbook_directory/"templates"/"default"/"#{fi.path}.erb"
          FileUtils.mkdir_p File.dirname(fpath) unless File.directory?(File.dirname(fpath))
          content = fi.template ? open(fi.template).read : fi.content
          File.open(fpath, "w") do |f|
            f << content
          end
        end
      end
      
      # compile the recipes
      # TODO
      def compile_recipes
      end
      
      def write_dna_json
        File.open(compile_directory/"dna.json", "w") do |f|
          f << JSON.generate({:recipes => ["poolparty"]})
        end
      end
      
      def compile_default_recipe(content)
        FileUtils.mkdir_p cookbook_directory/"recipes" unless ::File.directory?(cookbook_directory/"recipes")
        File.open(cookbook_directory/"recipes"/"default.rb", "w") do |f|
          f << content
        end
      end
      
      def write_solo_dot_rb
        content = <<-EOE
cookbook_path     "/etc/chef/cookbooks"
node_path         "/etc/chef/nodes"
log_level         :info
file_store_path  "/etc/chef"
file_cache_path  "/etc/chef"
        EOE
        
        File.open(compile_directory/"solo.rb", "w") do |f|
          f << content
        end
      end
      
    end
    
  end
  
end