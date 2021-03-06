# encoding: UTF-8

require File.expand_path('../spec_helper', __FILE__)

module ProjectSpecs
  describe 'Xcodeproj::PlistHelper' do
    before do
      Plist.implementation = Plist::FFI
      @plist = temporary_directory + 'plist'
    end

    describe 'In general' do
      extend SpecHelper::TemporaryDirectory

      it 'writes an XML plist file' do
        hash = { 'archiveVersion' => '1.0' }
        Plist::FFI::DevToolsCore.stubs(:load_xcode_frameworks).returns(nil)
        Plist.write_to_path(hash, @plist)
        result = Plist.read_from_path(@plist)
        result.should == hash
        @plist.read.should.include('?xml')
      end

      it 'reads an ASCII plist file' do
        dir = 'Sample Project/Cocoa Application.xcodeproj/'
        path = fixture_path(dir + 'project.pbxproj')
        result = Plist.read_from_path(path)
        result.keys.should.include?('archiveVersion')
      end

      it 'saves a plist file to be consistent with Xcode' do
        output = <<-PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>archiveVersion</key>
	<string>1.0</string>
</dict>
</plist>
        PLIST

        hash = { 'archiveVersion' => '1.0' }
        Plist::FFI::DevToolsCore.stubs(:load_xcode_frameworks).returns(nil)
        Plist.write_to_path(hash, @plist)
        @plist.read.should == output
      end
    end

    #-------------------------------------------------------------------------#

    describe 'Robustness' do
      extend SpecHelper::TemporaryDirectory

      it 'coerces the given path object to a string path' do
        # @plist is a Pathname
        Plist.write_to_path({}, @plist)
        Plist.read_from_path(@plist).should == {}
      end

      it "raises when the given path can't be coerced into a string path" do
        lambda { Plist.write_to_path({}, Object.new) }.should.raise TypeError
      end

      it "raises if the given path doesn't exist" do
        lambda { Plist.read_from_path('doesnotexist') }.should.raise Xcodeproj::Informative
      end

      it 'coerces the given hash to a Hash' do
        o = Object.new
        def o.to_hash
          { 'from' => 'object' }
        end
        Plist.write_to_path(o, @plist)
        Plist.read_from_path(@plist).should == { 'from' => 'object' }
      end

      it "raises when given a hash that can't be coerced to a Hash" do
        lambda { Plist.write_to_path(Object.new, @plist) }.should.raise TypeError
      end

      it 'coerces keys to strings' do
        Plist.write_to_path({ 1 => '1', :symbol => 'symbol' }, @plist)
        Plist.read_from_path(@plist).should == { '1' => '1', 'symbol' => 'symbol' }
      end

      it 'allows hashes, strings, booleans, numbers, and arrays of hashes and strings as values' do
        hash = {
          'hash' => { 'a hash' => 'in a hash' },
          'string' => 'string',
          'true_bool' => '1',
          'false_bool' => '0',
          'integer' => 42,
          'float' => 0.5,
          'array' => ['string in an array', { 'a hash' => 'in an array' }],
        }
        Plist.write_to_path(hash, @plist)
        Plist.read_from_path(@plist).should == hash
      end

      it 'coerces values to strings if it is a disallowed type' do
        Plist.write_to_path({ '1' => 9_999_999_999_999_999_999_999_999, 'symbol' => :symbol }, @plist)
        Plist.read_from_path(@plist).should == { '1' => '9999999999999999999999999', 'symbol' => 'symbol' }
      end

      it 'handles unicode characters in paths and strings' do
        plist = @plist.to_s + 'øµ'
        Plist.write_to_path({ 'café' => 'før yoµ' }, plist)
        Plist.read_from_path(plist).should == { 'café' => 'før yoµ' }
      end

      it 'raises if a plist contains any non-supported object type' do
        @plist.open('w') do |f|
          f.write <<-EOS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>uhoh</key>
  <date>2004-03-03T01:02:03Z</date>
</dict>
</plist>
EOS
        end
        lambda { Plist.read_from_path(@plist) }.should.raise TypeError
      end

      it 'raises if a plist array value contains any non-supported object type' do
        @plist.open('w') do |f|
          f.write <<-EOS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>uhoh</key>
  <array>
    <date>2004-03-03T01:02:03Z</date>
  </array>
</dict>
</plist>
EOS
        end
        lambda { Plist.read_from_path(@plist) }.should.raise TypeError
      end

      it 'raises if for whatever reason the value could not be converted to a CFTypeRef' do
        lambda do
          Plist.write_to_path({ 'invalid' => "\xCA" }, @plist)
        end.should.raise TypeError
      end

      it 'will not crash when using an empty path' do
        lambda do
          Plist.write_to_path({}, '')
        end.should.raise IOError
      end
    end

    #-------------------------------------------------------------------------#

    describe 'Xcode frameworks resilience' do
      extend SpecHelper::TemporaryDirectory

      after do
        if @original_xcode_path
          Plist::FFI::DevToolsCore.send(:remove_const, :XCODE_PATH)
          Plist::FFI::DevToolsCore.const_set(:XCODE_PATH, @original_xcode_path)
        end
      end

      def read_sample
        dir = 'Sample Project/Cocoa Application.xcodeproj/'
        path = fixture_path(dir + 'project.pbxproj')
        Plist.read_from_path(path)
      end

      def stub_xcode_path(stubbed_path)
        @original_xcode_path = Plist::FFI::DevToolsCore::XCODE_PATH
        Plist::FFI::DevToolsCore.send(:remove_const, :XCODE_PATH)
        Plist::FFI::DevToolsCore.const_set(:XCODE_PATH, stubbed_path)
      end

      def write_temp_file_and_compare(sample)
        temp_file = File.join(SpecHelper.temporary_directory, 'out.pbxproj')
        Plist.write_to_path(sample, temp_file)
        result = Plist.read_from_path(temp_file)

        sample.should == result
        File.new(temp_file).read.start_with?('<?xml').should == true
      end

      it 'will fallback to XML encoding if Xcode is not installed' do
        # Simulate this by calling `xcrun` with a non-existing tool
        stub_xcode_path(Pathname.new(`xcrun lol 2>/dev/null`))

        write_temp_file_and_compare(read_sample)
      end

      it 'will fallback to XML encoding if the user has not agreed to the Xcode license' do
        stub_xcode_path(Pathname.new('Agreeing to the Xcode/iOS license requires admin privileges, please re-run as root via sudo.'))

        write_temp_file_and_compare(read_sample)
      end

      it 'will fallback to XML encoding if Xcode functions cannot be found' do
        Plist::FFI::DevToolsCore.stubs(:load_xcode_frameworks).returns(Fiddle::Handle.new)

        write_temp_file_and_compare(read_sample)
      end

      it 'will fallback to XML encoding if Xcode methods return errors' do
        Plist::FFI::DevToolsCore::NSData.any_instance.stubs(:writeToFileAtomically).returns(false)

        write_temp_file_and_compare(read_sample)
      end

      it 'will fallback to XML encoding if Xcode classes cannot be found' do
        Plist::FFI::DevToolsCore::NSObject.stubs(:objc_class).returns(nil)

        write_temp_file_and_compare(read_sample)
      end
    end
  end
end
