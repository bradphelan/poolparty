require File.dirname(__FILE__) + '/../spec_helper'
require File.dirname(__FILE__) + '/../../lib/poolparty/helpers/binary'

describe "Binary" do
  before(:each) do
    Dir.stub!(:[]).and_return %w(init console)
  end
  it "should have the binary location set on Binary" do
    Binary.binary_directory.should == "./spec/helpers/../../lib/poolparty/helpers/../../../bin"
  end
  it "should be able to list the binaries in the bin directory" do
    Binary.available_binaries.should == %w(console init)
  end
  it "should be able to say the binary is in the binary_directory" do
    Binary.available_binaries.include?("console")
  end
end