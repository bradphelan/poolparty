require File.dirname(__FILE__) + '/../spec_helper'

module PoolParty
  module Plugin
   class  TestService < Plugin
      def initialize(o={}, e=nil, &block)
        super(&block)
      end
      def enable(o={})
        has_file(:name => "/etc/poolparty/lobos")
      end
    end 
  end
end

describe "Cloud" do
  describe "wrapped" do
    before(:each) do
      @obj = Object.new
      @pool = pool :just_pool do; end
    end
    it "should respond to the pool method outside the block" do
      @obj.respond_to?(:cloud).should == true
    end
    describe "global" do
      before(:each) do
        @cloud1 = cloud :pop do;end
      end
      it "should store the cloud in the global list of clouds" do    
        @obj.clouds.has_key?(:pop).should == true
      end
      it "should store the cloud" do
        @obj.cloud(:pop).should == @cloud1
      end
      it "should have set the using base on intantiation to ec2" do
        @cloud1.remoter_base.should_not == nil
      end
      it "should say the remoter_base is ec2 (by default)" do
        @cloud1.remoter_base.should == :ec2
      end
    end
    it "should return the cloud if the cloud key is already in the clouds list" do
      @cld = cloud :pop do;end
      @pool.cloud(:pop).should == @cld
    end
    describe "options" do
      before(:each) do
        reset!
        pool :options do
          user "bob"
          minimum_instances 100
          access_key "pool_access_key"
          cloud :apple do
            access_key "cloud_access_key"
          end
        end
      end
      it "should be able to grab the cloud from the pool" do
        clouds[:apple].should == pools[:options].cloud(:apple)
      end
      it "should take the options set on the pool" do
        pools[:options].minimum_instances.should == 100
      end
      it "should take the access_key option set from the cloud" do
        clouds[:apple].access_key.should == "cloud_access_key"
      end
      it "should take the option testing true from the superclass" do
        pools[:options].user.should == "bob"
        clouds[:apple].user.should == "bob"
      end
    end
    describe "block" do
      before(:each) do
        reset!
        pool :test do
          Cloud.new(:test) do
            # Inside cloud block
            testing true
            keypair "fake_keypair"
          end
        end
        @cloud = cloud :test
        @cloud.stub!(:plugin_store).and_return []
      end

      it "should be able to pull the pool from the cloud" do
        @cloud.parent == @pool
      end
      it "should have the outer pool listed as the parent of the inner cloud" do
        @pool = pool :knick_knack do
          cloud :paddy_wack do            
          end
        end
        cloud(:paddy_wack).parent.should == pool(:knick_knack)
      end
      it "should respond to a dsl_options method (from Dslify)" do
        @cloud.respond_to?(:dsl_options).should == true
      end
      describe "configuration" do
        before(:each) do
          reset!
          @cloud2 = Cloud.new(:test) do
            minimum_instances 1
            maximum_instances 2
          end
        end
        it "should be able to se the minimum_instances without the var" do
          @cloud2.minimum_instances.should == 1
        end
        it "should be able to se the maximum_instances with the =" do
          @cloud2.maximum_instances.should == 2
        end
      end
      describe "options" do
        it "should set the minimum_instances to 2" do
          @cloud.minimum_instances.should == 2
        end
        it "should set the maximum_instances to 5" do
          @cloud.maximum_instances.should == 5
        end
        it "should be able to set the minimum instances" do
          @cloud.minimum_instances 3
          @cloud.minimum_instances.should == 3
        end
        it "should be able to take a hash from configure and convert it to the options" do
          @cloud.set_vars_from_options( {:minimum_instances => 1, :maximum_instances => 10, :keypair => "friend"} )
          @cloud.minimum_instances.should == 1
        end
        describe "minimum_instances/maximum_instances as a range" do
          before(:each) do
            reset!
            @pool = pool :just_pool do
              cloud :app do
                instances 8..15
              end
            end
            @cloud = @pool.cloud(:app)
          end
          it "should set it's own cloud.tmp_path" do
            @cloud.tmp_path.should == "/tmp/poolparty/just_pool/app"
          end
          it "should set the minimum based on the range" do
            @cloud.minimum_instances.should == 8
          end
          it "should set the maximum based on the range set by instances" do
            @cloud.maximum_instances.should == 15
          end
        end
        describe "keypair" do
          before(:each) do
            reset!
          end
          it "should be able to define a keypair in the cloud" do
            @c = cloud :app do
              keypair "hotdog"
            end
            @c._keypairs.map {|a| a.basename }.include?("hotdog")
          end
          it "should take the pool parent's keypair if it's defined on the pool" do
            pool :pool do              
              cloud :app do
                keypair "ney"
              end
            end            
            clouds[:app]._keypairs.first.stub!(:exists?).and_return true
            clouds[:app]._keypairs.size.should == 2
          end
          it "should default to ~/.ssh/id_rsa if none are defined" do
            ::File.stub!(:exists?).and_return(false)
            ::File.stub!(:exists?).with(File.expand_path("#{ENV["HOME"]}/.ssh/id_jokes")).and_return(true)
            pool :pool do
              cloud :app do
                keypair "id_jokes"
              end
            end
            clouds[:app].keypair.full_filepath.should match(/\.ssh\/id_jokes/)
          end
        end
        describe "Manifest" do
          before(:each) do
            reset!
            stub_list_from_remote_for(@cloud)
            @cloud = TestClass.new :test_more_manifest do
              has_file(:name => "/etc/httpd/http.conf") do
                content <<-EOE
                  hello my lady
                EOE
              end
              enable :haproxy
              has_gem_package(:name => "poolparty")
              has_package(:name => "dummy")            
            end
            context_stack.push @cloud
          end
          it "should it should have the method build_manifest" do
            @cloud.respond_to?(:build_manifest).should == true
          end
          it "should make a new 'haproxy' class" do
            @cloud.should_receive(:haproxy)
            @cloud.add_optional_enabled_services
          end
          it "should have at least 3 resources" do            
            @cloud.send :add_poolparty_base_requirements
            @cloud.ordered_resources.size.should > 2
          end
          it "should receive add_poolparty_base_requirements before building the manifest" do
            @cloud.should_receive(:add_poolparty_base_requirements).once
            @cloud.before_create
          end
          after(:each) do
            context_stack.pop
          end
          describe "add_poolparty_base_requirements" do
            before(:each) do
              reset!            
              @cloud.instance_eval do
                @heartbeat = nil
              end
              @hb = PoolParty::Plugin::Heartbeat.new
            end
            it "should call enable on the plugin call" do
              @hb = PoolParty::Plugin::Heartbeat.new
              PoolParty::Plugin::Heartbeat.stub!(:new).and_return @hb
              
              @cloud.send :add_poolparty_base_requirements
              @cloud.heartbeat.should == @hb
            end
            describe "after adding" do
              before(:each) do
                stub_list_from_remote_for(@cloud)
                @cloud.send :add_poolparty_base_requirements
              end
              describe "resources" do
                before(:each) do
                  reset!
                  cloud :tester do
                    test_service
                  end
                  @service = clouds[:tester].ordered_resources.select {|hsh|
                    hsh.to_properties_hash.name == "test_service"
                    }.first
                  @files = @service.resource(:file)
                end
                it "should have a file resource" do
                  @files.first.nil?.should == false
                end
                it "should have an array of lines" do
                  @files.class.should == Array
                end
                it "should have the file /etc/poolparty/lobos" do
                  @files.first.name.should == "/etc/poolparty/lobos"
                end
              end
            end
          end
          describe "building" do
            before(:each) do            
              str = "master 192.168.0.1
              node1 192.168.0.2"
              @sample_instances_list = [{:ip => "192.168.0.1", :name => "master"}, {:ip => "192.168.0.2", :name => "node1"}]
              @ris = @sample_instances_list.map {|h| PoolParty::Remote::RemoteInstance.new(h) }
              
              stub_remoter_for(@cloud)
              
              @manifest = @cloud.build_manifest
            end
            it "should return a string when calling build_manifest" do
              @manifest.class.should == String
            end
            it "should have a comment of # file in the manifest as described by the has_file" do
              @manifest.should =~ /template \"\/etc\/httpd\/http.conf\" do/
            end
            it "should have the comment of a package in the manifest" do
              @manifest.should =~ /package "dummy" do/
            end
            it "should have the comment for haproxy in the manifest" do
              @manifest.should =~ /haproxy/
            end
            it "should include the poolparty gem" do
              pending
            end
          end

          describe "building with an existing manifest" do
            before(:each) do
              @file = "/etc/puppet/manifests/nodes/nodes.pp"
              @file.stub!(:read).and_return "nodes generate"
              ::FileTest.stub!(:file?).with("/etc/poolparty/poolparty.pp").and_return true
              @cloud.stub!(:open).with("/etc/poolparty/poolparty.pp").and_return @file
            end
            it "should not call resources_string_from_resources if the file /etc/puppet/manifests/nodes/nodes.pp exists" do
              @cloud.should_not_receive(:add_poolparty_base_requirements)
              @cloud.build_manifest
            end
            it "should build from the existing file" do
              @cloud.build_manifest.should == "nodes generate"
            end
          end
        end
      end
      
      describe "JSON" do
        before(:each) do
          pool :jason do
            user "fred"
            minimum_instances 10
            access_key "pool_a_key"
            cloud :stratus do
              keypair "fake_keypair"
              access_key "cloud_a_key"
            end
          end
          
        end
        it "should have to_json method" do
          clouds[:stratus].to_json.class.should == String
        end
      end

      # describe "instances" do
      #   before(:each) do
      #     @cloud3 = cloud :pop do;keypair "fake_keypair";end
      #     stub_list_from_remote_for(@cloud3)
      #   end
      #   it "should respond to the method master" do
      #     @cloud3.master.should_not be_nil
      #     @cloud3.respond_to?(:master).should == true
      #   end
      #   it "should return a master that is not nil" do
      #     @cloud3.master.should_not be_nil
      #   end
      # end
    end
  end
end
