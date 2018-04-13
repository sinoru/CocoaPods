require File.expand_path('../../../spec_helper', __FILE__)

module Pod
  class Target
    describe BuildSettings do
      def pod(pod_target, test_xcconfig = false)
        BuildSettings::Pod.new(pod_target, test_xcconfig)
      end

      def aggregate(aggregate_target, configuration_name = 'Release')
        BuildSettings::Aggregate.new(aggregate_target, configuration_name)
      end

      #---------------------------------------------------------------------#

      describe '::add_spec_build_settings_to_xcconfig' do
        it 'adds the libraries of the xcconfig' do
          xcconfig = Xcodeproj::Config.new
          consumer = stub('consumer',
                          :pod_target_xcconfig => {},
                          :libraries => ['xml2'],
                          :frameworks => [],
                          :weak_frameworks => [],
                          :platform_name => :ios,
                          )
          @sut.add_spec_build_settings_to_xcconfig(consumer, xcconfig)
          xcconfig.to_hash['OTHER_LDFLAGS'].should == '-l"xml2"'
        end

        it 'check that subspec subsets are removed from frameworks search paths' do
          target1 = stub('target1',
                          :specs => %w(A, B),
                          :should_build? => true,
                          :requires_frameworks? => true,
                          :configuration_build_dir => 'AB',
                          :uses_swift? => false,
                        )
          target2 = stub('target2',
                          :specs => ['B'],
                          :should_build? => true,
                          :requires_frameworks? => true,
                          :configuration_build_dir => 'B',
                          :uses_swift? => false,
                        )
          dependent_targets = [target1, target2]
          build_settings = @sut.search_paths_for_dependent_targets(nil, dependent_targets)
          build_settings['FRAMEWORK_SEARCH_PATHS'].should == '"AB"'
        end

        it 'adds the libraries of the xcconfig for a static framework' do
          spec = stub('spec', :test_specification? => false)
          target_definition = stub('target_definition', :inheritance => 'search_paths')
          consumer = stub('consumer',
                          :pod_target_xcconfig => {},
                          :libraries => ['xml2'],
                          :frameworks => [],
                          :weak_frameworks => [],
                          :platform_name => :ios,
                          )
          file_accessor = stub('file_accessor',
                                :spec => spec,
                                :spec_consumer => consumer,
                                :vendored_static_frameworks => [],
                                :vendored_dynamic_frameworks => [],
                                :vendored_static_libraries => [],
                                :vendored_dynamic_libraries => [],
                              )
          pod_target = stub('pod_target',
                            :name => 'BananaLib',
                            :sandbox => config.sandbox,
                            :should_build? => true,
                            :requires_frameworks? => true,
                            :static_framework? => true,
                            :dependent_targets => [],
                            :file_accessors => [file_accessor],
                            )
          pod_targets = [pod_target]
          aggregate_target = stub('aggregate_target',
                                  :target_definition => target_definition,
                                  :pod_targets => pod_targets,
                                  :search_paths_aggregate_targets => [],
                                  :pod_targets_to_link => pod_targets,
                                  )
          xcconfig = Xcodeproj::Config.new
          @sut.generate_vendored_build_settings(aggregate_target, pod_targets, xcconfig)
          xcconfig.to_hash['OTHER_LDFLAGS'].should == '-l"xml2"'
        end

        it 'checks OTHER_LDFLAGS and FRAMEWORK_SEARCH_PATHS for a vendored dependencies to a static framework' do
          spec = stub('spec', :test_specification? => false)
          target_definition = stub('target_definition', :inheritance => 'search_paths')
          consumer = stub('consumer',
                          :pod_target_xcconfig => {},
                          :libraries => ['xml2'],
                          :frameworks => [],
                          :weak_frameworks => [],
                          :platform_name => :ios,
                          )
          file_accessor = stub('file_accessor',
                                :spec => spec,
                                :spec_consumer => consumer,
                                :vendored_static_frameworks => [config.sandbox.root + 'StaticFramework.framework'],
                                :vendored_static_libraries => [config.sandbox.root + 'StaticLibrary.a'],
                                :vendored_dynamic_frameworks => [config.sandbox.root + 'VendoredFramework.framework'],
                                :vendored_dynamic_libraries => [config.sandbox.root + 'VendoredDyld.dyld'],
                              )
          dep_target = stub('dep_target',
                            :name => 'BananaLib',
                            :sandbox => config.sandbox,
                            :should_build? => false,
                            :requires_frameworks? => true,
                            :static_framework? => false,
                            :dependent_targets => [],
                            :file_accessors => [file_accessor],
                            )
          dep_targets = [dep_target]
          target = stub('target',
                        :target_definition => target_definition,
                        :pod_targets => dep_targets,
                        :search_paths_aggregate_targets => [],
                        :static_framework => true,
                        :pod_targets_to_link => dep_targets,
                        )
          xcconfig = Xcodeproj::Config.new
          @sut.generate_vendored_build_settings(target, dep_targets, xcconfig, true)
          xcconfig.to_hash['OTHER_LDFLAGS'].should == '-l"StaticLibrary" -l"VendoredDyld" -l"xml2" -framework "StaticFramework" -framework "VendoredFramework"'
          xcconfig.to_hash['FRAMEWORK_SEARCH_PATHS'].should == '"${PODS_ROOT}/."'
        end

        it 'quotes OTHER_LDFLAGS to properly handle spaces' do
          framework_path = config.sandbox.root + 'Sample/Framework with Spaces.framework'
          library_path = config.sandbox.root + 'Sample/libSample Lib.a'

          xcconfig = Xcodeproj::Config.new
          @sut.add_framework_build_settings(framework_path, xcconfig, config.sandbox.root)
          @sut.add_library_build_settings(library_path, xcconfig, config.sandbox.root)

          hash_config = xcconfig.to_hash
          hash_config['OTHER_LDFLAGS'].should == '-l"Sample Lib" -framework "Framework with Spaces"'
        end

        it 'check that include_ld_flags being false doesnt generate OTHER_LDFLAGS' do
          spec = stub('spec', :test_specification? => false)
          target_definition = stub('target_definition', :inheritance => 'search_paths')
          consumer = stub('consumer',
                          :pod_target_xcconfig => {},
                          :libraries => ['xml2'],
                          :frameworks => [],
                          :weak_frameworks => [],
                          :platform_name => :ios,
                          )
          file_accessor = stub('file_accessor',
                                :spec => spec,
                                :spec_consumer => consumer,
                                :vendored_static_frameworks => [config.sandbox.root + 'StaticFramework.framework'],
                                :vendored_static_libraries => [config.sandbox.root + 'StaticLibrary.a'],
                                :vendored_dynamic_frameworks => [config.sandbox.root + 'VendoredFramework.framework'],
                                :vendored_dynamic_libraries => [config.sandbox.root + 'VendoredDyld.dyld'],
                              )
          dep_target = stub('dep_target',
                            :name => 'BananaLib',
                            :sandbox => config.sandbox,
                            :should_build? => false,
                            :requires_frameworks? => true,
                            :static_framework? => false,
                            :dependent_targets => [],
                            :file_accessors => [file_accessor],
                            )
          dep_targets = [dep_target]
          target = stub('target',
                        :target_definition => target_definition,
                        :pod_targets => dep_targets,
                        :search_paths_aggregate_targets => [],
                        )
          xcconfig = Xcodeproj::Config.new
          @sut.generate_vendored_build_settings(target, dep_targets, xcconfig, false)
          xcconfig.to_hash['OTHER_LDFLAGS'].should.nil?
          xcconfig.to_hash['FRAMEWORK_SEARCH_PATHS'].should == '"${PODS_ROOT}/."'
        end

        it 'makes sure setting from search_paths get propagated for static frameworks' do
          target_definition = stub('target_definition', :inheritance => 'search_paths')
          spec = stub('spec', :test_specification? => false)
          consumer = stub('consumer',
                          :spec => spec,
                          :pod_target_xcconfig => {},
                          :libraries => ['xml2'],
                          :frameworks => ['Foo'],
                          :weak_frameworks => [],
                          :platform_name => :ios,
                          )
          file_accessor = stub('file_accessor',
                                :spec => spec,
                                :spec_consumer => consumer,
                                :vendored_static_frameworks => [],
                                :vendored_dynamic_frameworks => [],
                                :vendored_static_libraries => [],
                                :vendored_dynamic_libraries => [],
                              )
          pod_target = stub('pod_target',
                            :name => 'BananaLib',
                            :sandbox => config.sandbox,
                            :should_build? => true,
                            :requires_frameworks? => true,
                            :static_framework? => true,
                            :dependent_targets => [],
                            :file_accessors => [file_accessor],
                            :product_basename => 'Foo',
                            :spec_consumers => [consumer],
                            )
          pod_target.stubs(:build_settings => pod(pod_target))
          pod_targets = [pod_target]
          aggregate_target = stub('aggregate_target',
                                  :target_definition => target_definition,
                                  :pod_targets => pod_targets,
                                  :pod_targets_for_build_configuration => pod_targets,
                                  :search_paths_aggregate_targets => [],
                                  )
          aggregate_target.stubs(:build_settings => aggregate(aggregate_target))
          test_aggregate_target = stub('test_aggregate_target',
                                        :target_definition => target_definition,
                                        :pod_targets => [],
                                        :pod_targets_for_build_configuration => [],
                                        :search_paths_aggregate_targets => [aggregate_target],
                                        :requires_frameworks? => true,
                                        :podfile => stub('Podfile', set_arc_compatibility_flag?: false),
                                      )

          aggregate(test_aggregate_target).other_ldflags.should == %w[-framework "Foo"]
        end
      end

      #---------------------------------------------------------------------#

      describe '::add_developers_frameworks_if_needed' do
        it 'adds the developer frameworks search paths to the xcconfig if SenTestingKit has been detected' do
          xcconfig = BuildSettings.new(stub('Target'))
          xcconfig.stubs(:frameworks => %w(SenTestingKit))
          frameworks_search_paths = xcconfig.framework_search_paths
          frameworks_search_paths.should == %w($(PLATFORM_DIR)/Developer/Library/Frameworks)
        end

        it 'adds the developer frameworks search paths to the xcconfig if XCTest has been detected' do
          xcconfig = BuildSettings.new(stub('Target'))
          xcconfig.stubs(:frameworks => %w(XCTest))
          frameworks_search_paths = xcconfig.framework_search_paths
          frameworks_search_paths.should == %w($(PLATFORM_DIR)/Developer/Library/Frameworks)
        end
      end

      #---------------------------------------------------------------------#

      describe '::add_language_specific_settings' do
        it 'does not add OTHER_SWIFT_FLAGS to the xcconfig if the target does not use swift' do
          target = fixture_pod_target('integration/Reachability/Reachability.podspec')
          build_settings = pod(target)
          other_swift_flags = build_settings.xcconfig.to_hash['OTHER_SWIFT_FLAGS']
          other_swift_flags.should.be.nil
        end

        it 'does not add the -suppress-warnings flag to the xcconfig if the target uses swift, but does not inhibit warnings' do
          target = fixture_pod_target('integration/Reachability/Reachability.podspec')
          target.stubs(:uses_swift? => true, :inhibit_warnings? => false)
          build_settings = pod(target)
          other_swift_flags = build_settings.xcconfig.to_hash['OTHER_SWIFT_FLAGS']
          other_swift_flags.should.not.include '-suppress-warnings'
        end

        it 'adds the -suppress-warnings flag to the xcconfig if the target uses swift and inhibits warnings' do
          target = fixture_pod_target('integration/Reachability/Reachability.podspec')
          target.stubs(:uses_swift? => true, :inhibit_warnings? => true)
          build_settings = pod(target)
          other_swift_flags = build_settings.xcconfig.to_hash['OTHER_SWIFT_FLAGS']
          other_swift_flags.should.include '-suppress-warnings'
        end
      end

      #---------------------------------------------------------------------#

      describe 'concerning settings for file accessors' do
        it 'does not propagate framework or libraries from a test specification to an aggregate target' do
          spec = stub('spec', :test_specification? => true)
          consumer = stub('consumer',
                          :libraries => ['xml2'],
                          :frameworks => ['XCTest'],
                          :weak_frameworks => [],
                          :spec => spec,
                          )
          file_accessor = stub('file_accessor',
                                :spec => spec,
                                :spec_consumer => consumer,
                                :vendored_static_frameworks => [config.sandbox.root + 'StaticFramework.framework'],
                                :vendored_static_libraries => [config.sandbox.root + 'StaticLibrary.a'],
                                :vendored_dynamic_frameworks => [config.sandbox.root + 'VendoredFramework.framework'],
                                :vendored_dynamic_libraries => [config.sandbox.root + 'VendoredDyld.dyld'],
                              )
          pod_target = stub('pod_target',
                            :file_accessors => [file_accessor],
                            :requires_frameworks? => true,
                            :dependent_targets => [],
                            :recursive_dependent_targets => [],
                            :sandbox => config.sandbox,
                            :include_in_build_config? => true,
                            :should_build? => false,
                            :spec_consumers => [consumer],
                            :static_framework? => false,
                            :product_basename => 'PodTarget'
                            )
          pod_target.stubs(:build_settings => pod(pod_target))
          target_definition = stub('target_definition', :inheritance => 'complete', :abstract? => false, :podfile => Podfile.new)
          aggregate_target = fixture_aggregate_target([pod_target], target_definition)
          aggregate(aggregate_target).other_ldflags.should.not.include '-framework'
        end

        # TODO: move to pod target
        it 'propagates correct frameworks or libraries to both test and non test xcconfigs' do
          spec = stub('spec', :test_specification? => false)
          consumer = stub('consumer',
                          :libraries => [],
                          :frameworks => [],
                          :weak_frameworks => [],
                          :spec => spec,
                          )
          file_accessor = stub('file_accessor',
                                :spec => spec,
                                :spec_consumer => consumer,
                                :vendored_static_frameworks => [config.sandbox.root + 'StaticFramework.framework'],
                                :vendored_static_libraries => [config.sandbox.root + 'StaticLibrary.a'],
                                :vendored_dynamic_frameworks => [config.sandbox.root + 'VendoredFramework.framework'],
                                :vendored_dynamic_libraries => [config.sandbox.root + 'VendoredDyld.dyld'],
                              )
          test_spec = stub('test_spec', :test_specification? => true)
          test_consumer = stub('test_consumer',
                                :libraries => ['xml2'],
                                :frameworks => ['XCTest'],
                                :weak_frameworks => [],
                                :spec => test_spec,
                              )
          test_file_accessor = stub('test_file_accessor',
                                    :spec => test_spec,
                                    :spec_consumer => test_consumer,
                                    :vendored_static_frameworks => [],
                                    :vendored_static_libraries => [],
                                    :vendored_dynamic_frameworks => [],
                                    :vendored_dynamic_libraries => [],
                                    )
          pod_target = stub('pod_target',
                            :file_accessors => [file_accessor, test_file_accessor],
                            :requires_frameworks? => true,
                            :dependent_targets => [],
                            :sandbox => config.sandbox,
                            )
          xcconfig = Xcodeproj::Config.new
          @sut.add_settings_for_file_accessors_of_target(nil, pod_target, xcconfig, true, false)
          xcconfig.to_hash['OTHER_LDFLAGS'].should == '-l"StaticLibrary" -l"VendoredDyld" -framework "StaticFramework" -framework "VendoredFramework"'
          test_xcconfig = Xcodeproj::Config.new
          @sut.add_settings_for_file_accessors_of_target(nil, pod_target, test_xcconfig, true, true)
          test_xcconfig.to_hash['OTHER_LDFLAGS'].should == '-l"StaticLibrary" -l"VendoredDyld" -l"xml2" -framework "StaticFramework" -framework "VendoredFramework" -framework "XCTest"'
        end

        # TODO: move to aggregate target
        it 'does propagate framework or libraries from a non test specification to an aggregate target' do
          spec = stub('spec', :test_specification? => false)
          consumer = stub('consumer',
                          :libraries => ['xml2'],
                          :frameworks => ['XCTest'],
                          :weak_frameworks => [],
                          :spec => spec,
                          )
          file_accessor = stub('file_accessor',
                                :spec => spec,
                                :spec_consumer => consumer,
                                :vendored_static_frameworks => [config.sandbox.root + 'StaticFramework.framework'],
                                :vendored_static_libraries => [config.sandbox.root + 'StaticLibrary.a'],
                                :vendored_dynamic_frameworks => [config.sandbox.root + 'VendoredFramework.framework'],
                                :vendored_dynamic_libraries => [config.sandbox.root + 'VendoredDyld.dyld'],
                              )
          pod_target = stub('pod_target',
                            :file_accessors => [file_accessor],
                            :requires_frameworks? => true,
                            :dependent_targets => [],
                            :sandbox => config.sandbox,
                            )
          target_definition = stub('target_definition', :inheritance => 'complete')
          aggregate_target = stub('aggregate_target', :target_definition => target_definition)
          xcconfig = Xcodeproj::Config.new
          @sut.add_settings_for_file_accessors_of_target(aggregate_target, pod_target, xcconfig)
          xcconfig.to_hash['OTHER_LDFLAGS'].should.be == '-l"StaticLibrary" -l"VendoredDyld" -l"xml2" -framework "StaticFramework" -framework "VendoredFramework" -framework "XCTest"'
        end

        # Move to pod target
        it 'does propagate framework or libraries to a nil aggregate target' do
          spec = stub('spec', :test_specification? => false)
          consumer = stub('consumer',
                          :libraries => ['xml2'],
                          :frameworks => ['XCTest'],
                          :weak_frameworks => [],
                          :spec => spec,
                          )
          file_accessor = stub('file_accessor',
                                :spec => spec,
                                :spec_consumer => consumer,
                                :vendored_static_frameworks => [config.sandbox.root + 'StaticFramework.framework'],
                                :vendored_static_libraries => [config.sandbox.root + 'StaticLibrary.a'],
                                :vendored_dynamic_frameworks => [config.sandbox.root + 'VendoredFramework.framework'],
                                :vendored_dynamic_libraries => [config.sandbox.root + 'VendoredDyld.dyld'],
                              )
          pod_target = stub('pod_target',
                            :file_accessors => [file_accessor],
                            :requires_frameworks? => true,
                            :dependent_targets => [],
                            :sandbox => config.sandbox,
                            )
          xcconfig = Xcodeproj::Config.new
          @sut.add_settings_for_file_accessors_of_target(nil, pod_target, xcconfig)
          xcconfig.to_hash['OTHER_LDFLAGS'].should.be == '-l"StaticLibrary" -l"VendoredDyld" -l"xml2" -framework "StaticFramework" -framework "VendoredFramework" -framework "XCTest"'
        end
      end

      # Move all to aggregate
      describe 'for proper other ld flags' do
        def stub_aggregate_target(pod_targets, target_definition = nil, search_paths_aggregate_targets: [])
          target_definition.stubs(:abstract? => false) unless target_definition.respond_to?(:abstract?)
          fixture_aggregate_target(pod_targets, target_definition).tap do |aggregate_target|
            aggregate_target.search_paths_aggregate_targets.concat(search_paths_aggregate_targets).freeze
          end
        end

        before do
          @root = fixture('banana-lib')
          @path_list = Sandbox::PathList.new(@root)
          @spec = fixture_spec('banana-lib/BananaLib.podspec')
          @spec_consumer = @spec.consumer(:ios)
          @accessor = Pod::Sandbox::FileAccessor.new(@path_list, @spec_consumer)
        end

        it 'should not include static framework other ld flags when inheriting search paths' do
          target_definition = stub('target_definition', :inheritance => 'search_paths')
          pod_target = stub('pod_target', :sandbox => config.sandbox, :include_in_build_config? => true)
          aggregate_target = stub_aggregate_target([pod_target], target_definition)
          xcconfig = aggregate(aggregate_target).xcconfig
          xcconfig.to_hash['LIBRARY_SEARCH_PATHS'].should == '"${PODS_ROOT}/../../spec/fixtures/banana-lib"'
          xcconfig.to_hash['FRAMEWORK_SEARCH_PATHS'].should == '"${PODS_ROOT}/../../spec/fixtures/banana-lib"'
          xcconfig.to_hash['OTHER_LDFLAGS'].should.be.nil
        end

        it 'should include static framework other ld flags when inheriting search paths but explicitly declared' do
          target_definition = stub('target_definition', :inheritance => 'search_paths')
          pod_target = stub('pod_target', :name => 'BananaLib', :sandbox => config.sandbox)
          aggregate_target = stub_aggregate_target([pod_target], target_definition)
          xcconfig = Xcodeproj::Config.new
          @sut.add_static_dependency_build_settings(aggregate_target, pod_target, xcconfig, @accessor, true)
          xcconfig.to_hash['LIBRARY_SEARCH_PATHS'].should == '"${PODS_ROOT}/../../spec/fixtures/banana-lib"'
          xcconfig.to_hash['FRAMEWORK_SEARCH_PATHS'].should == '"${PODS_ROOT}/../../spec/fixtures/banana-lib"'
          xcconfig.to_hash['OTHER_LDFLAGS'].should == '-l"Bananalib" -framework "Bananalib"'
        end

        it 'should include static framework other ld flags when not inheriting search paths' do
          target_definition = stub('target_definition', :inheritance => 'complete')
          aggregate_target = stub_aggregate_target([], target_definition)
          pod_target = stub('pod_target', :sandbox => config.sandbox)
          xcconfig = Xcodeproj::Config.new
          @sut.add_static_dependency_build_settings(aggregate_target, pod_target, xcconfig, @accessor, true)
          xcconfig.to_hash['LIBRARY_SEARCH_PATHS'].should == '"${PODS_ROOT}/../../spec/fixtures/banana-lib"'
          xcconfig.to_hash['FRAMEWORK_SEARCH_PATHS'].should == '"${PODS_ROOT}/../../spec/fixtures/banana-lib"'
          xcconfig.to_hash['OTHER_LDFLAGS'].should == '-l"Bananalib" -framework "Bananalib"'
        end

        it 'should include static framework for pod targets' do
          pod_target = stub('pod_target', :sandbox => config.sandbox)
          xcconfig = Xcodeproj::Config.new
          @sut.add_static_dependency_build_settings(nil, pod_target, xcconfig, @accessor, true)
          xcconfig.to_hash['LIBRARY_SEARCH_PATHS'].should == '"${PODS_ROOT}/../../spec/fixtures/banana-lib"'
          xcconfig.to_hash['FRAMEWORK_SEARCH_PATHS'].should == '"${PODS_ROOT}/../../spec/fixtures/banana-lib"'
          xcconfig.to_hash['OTHER_LDFLAGS'].should == '-l"Bananalib" -framework "Bananalib"'
        end

        it 'should link static dependency for pod targets' do
          pod_target = stub('pod_target', :name => 'BananaLib', :sandbox => config.sandbox)
          @sut.links_dependency?(nil, pod_target).should.be.true
        end

        it 'should link static dependency when target explicitly specifies it' do
          target_definition = stub('target_definition', :inheritance => 'complete')
          pod_target = stub('pod_target', :name => 'BananaLib', :sandbox => config.sandbox)
          aggregate_target = stub_aggregate_target([pod_target], target_definition)
          @sut.links_dependency?(aggregate_target, pod_target).should.be.true
        end

        it 'should link static dependency when target explicitly specifies it even with search paths' do
          target_definition = stub('target_definition', :inheritance => 'search_paths')
          pod_target = stub('pod_target', :name => 'BananaLib', :sandbox => config.sandbox)
          aggregate_target = stub_aggregate_target([pod_target], target_definition)
          @sut.links_dependency?(aggregate_target, pod_target).should.be.true
        end

        it 'should not link static dependency when inheriting search paths and parent includes dependency' do
          parent_target_definition = stub
          child_target_definition = stub('child_target_definition', :inheritance => 'search_paths')
          pod_target = stub('pod_target', :name => 'BananaLib', :sandbox => config.sandbox)
          parent_aggregate_target = stub_aggregate_target([pod_target], parent_target_definition)
          child_aggregate_target = stub_aggregate_target([], child_target_definition, :search_paths_aggregate_targets => [parent_aggregate_target])
          @sut.links_dependency?(child_aggregate_target, pod_target).should.be.false
        end

        it 'should link static transitive dependencies if the parent does not link them' do
          child_pod_target = stub('child_pod_target', :name => 'ChildPod', :sandbox => config.sandbox)
          parent_pod_target = stub('parent_pod_target', :name => 'ParentPod', :sandbox => config.sandbox, :dependent_targets => [child_pod_target])

          parent_target_definition = stub
          child_target_definition = stub('child_target_definition', :inheritance => 'search_paths')

          parent_aggregate_target = stub_aggregate_target([], parent_target_definition)
          child_aggregate_target = stub_aggregate_target([parent_pod_target, child_pod_target], child_target_definition, :search_paths_aggregate_targets => [parent_aggregate_target])
          @sut.links_dependency?(child_aggregate_target, child_pod_target).should.be.true
          @sut.links_dependency?(child_aggregate_target, parent_pod_target).should.be.true
        end

        it 'should link static only transitive dependencies that the parent does not link' do
          child_pod_target = stub('child_pod_target', :name => 'ChildPod', :sandbox => config.sandbox)
          parent_pod_target = stub('parent_pod_target', :name => 'ParentPod', :sandbox => config.sandbox, :dependent_targets => [child_pod_target])

          parent_target_definition = stub
          child_target_definition = stub('child_target_definition', :inheritance => 'search_paths')

          parent_aggregate_target = stub('parent_aggregate_target', :target_definition => parent_target_definition, :pod_targets => [child_pod_target], :search_paths_aggregate_targets => [], :pod_targets_to_link => [child_pod_target])
          child_aggregate_target = stub('child_aggregate_target', :target_definition => child_target_definition, :pod_targets => [parent_pod_target, child_pod_target], :search_paths_aggregate_targets => [parent_aggregate_target], :pod_targets_to_link => [parent_pod_target])
          @sut.links_dependency?(child_aggregate_target, child_pod_target).should.be.false
          @sut.links_dependency?(child_aggregate_target, parent_pod_target).should.be.true
        end
      end

      #---------------------------------------------------------------------#
    end
  end
end
