module Pod
  class Target
    class BuildSettings
      PLURAL_SETTINGS = Set.new %w[
        ALTERNATE_PERMISSIONS_FILES
        ARCHS
        BUILD_VARIANTS
        EXCLUDED_SOURCE_FILE_NAMES
        FRAMEWORK_SEARCH_PATHS
        GCC_PREPROCESSOR_DEFINITIONS
        GCC_PREPROCESSOR_DEFINITIONS_NOT_USED_IN_PRECOMPS
        HEADER_SEARCH_PATHS
        INFOPLIST_PREPROCESSOR_DEFINITIONS
        LD_RUNPATH_SEARCH_PATHS
        LIBRARY_SEARCH_PATHS
        OTHER_CFLAGS
        OTHER_CPLUSPLUSFLAGS
        OTHER_LDFLAGS
        OTHER_SWIFT_FLAGS
        REZ_SEARCH_PATHS
        SECTORDER_FLAGS
        SWIFT_ACTIVE_COMPILATION_CONDITIONS
        SWIFT_INCLUDE_PATHS
        WARNING_CFLAGS
        WARNING_LDFLAGS
      ]

      CONFIGURATION_BUILD_DIR_VARIABLE = '${PODS_CONFIGURATION_BUILD_DIR}'.freeze

      def self.memoized(method_name)
        method = instance_method(method_name)

        define_method(method_name) do
          @__memoized ||= Hash.new
          @__memoized.fetch(method_name) { @__memoized[method_name] = method.bind(self).call }
        end

        method_name
      end

      def __clear__
        @__memoized = nil
      end

      def self.build_setting(method_name)
        (@build_settings_names ||= []) << method_name.to_s.upcase
        method_name
      end

      def self.build_settings_names
        @build_settings_names
      end

      attr_reader :target

      def initialize(target)
        @target = target
      end

      build_setting def gcc_preprocessor_definitions
        %w[COCOAPODS=1]
      end

      build_setting def header_search_paths
        []
      end

      build_setting def library_search_paths
        []
      end

      build_setting def framework_search_paths
        if frameworks.include?("XCTest") || frameworks.include?("SenTestingKit")
          [ "$(PLATFORM_DIR)/Developer/Library/Frameworks" ]
        else
          []
        end
      end

      memoized build_setting def other_cflags
        module_map_files.map {|f| "-fmodule-map-file=#{f}" }
      end

      def module_map_files
        []
      end

      def frameworks
        []
      end

      def weak_frameworks
        []
      end

      def libraries
        []
      end

      def requires_objc_linker_flag?
        false
      end

      def requires_fobjc_arc?
        false
      end

      memoized build_setting def other_ldflags
        ld_flags = []
        ld_flags << '-ObjC' if requires_objc_linker_flag?
        if requires_fobjc_arc?
          ld_flags << '-fobjc-arc'
        end
        libraries.each {|l| ld_flags << %(-l"#{l}") }
        frameworks.each {|f| ld_flags << '-framework' << %("#{f}") }
        weak_frameworks.each {|f| ld_flags << '-weak_framework' << %("#{f}") }
        ld_flags
      end

      # attribute 'OTHER_LDFLAGS', build_setting: :plural, memoized: true, sorted: false, unique: false do

      # end

      # attribute 'FRAMEWORK_SEARCH_PATHS', build_setting: :plural, memoized: true, sorted: true, unique: true do

      # end

      memoized build_setting def other_swift_flags
        return unless target.uses_swift?
        flags = %w[-D COCOAPODS]
        flags.concat module_map_files.flat_map {|f| ['-Xcc', "-fmodule-map-file=#{f}"] }
      end

      build_setting def swift_active_compilation_conditions
        []
      end

      build_setting def swift_include_paths
        []
      end

      build_setting def pods_build_dir
        '${BUILD_DIR}'
      end

      memoized build_setting def code_sign_identity
        return unless target.requires_frameworks?
        return unless target.platform.to_sym == :osx
        ''
      end

      build_setting def pods_configuration_build_dir
        '${PODS_BUILD_DIR}/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)'
      end

      def _ld_runpath_search_paths(requires_host_target: false, test_bundle: false)
        if target.platform.symbolic_name == :osx
          ["'@executable_path/../Frameworks'",
            test_bundle ? "'@loader_path/../Frameworks'" : "'@loader_path/Frameworks'"]
        else
          paths = [
            "'@executable_path/Frameworks'",
            "'@loader_path/Frameworks'",
          ]
          paths << "'@executable_path/../../Frameworks'" if requires_host_target
          paths
        end
      end

      memoized def xcconfig
        settings = add_inherited_to_plural(to_h)
        Xcodeproj::Config.new(settings)
      end

      def generate
        __clear__
        xcconfig
      end

      def save_as(path)
        xcconfig.save_as(path)
      end

      def to_h
        self.class.build_settings_names.reduce({}) {|a, e| a[e] = send(e.downcase); a }
      end

      def add_inherited_to_plural(hash)
        hash.map do |key, value|
          next [key, '$(inherited)'] if value.nil?
          if PLURAL_SETTINGS.include?(key)
            raise ArgumentError, "#{key} is a plural setting, cannot have #{value.inspect} as its value" unless value.is_a? Array

            value = "$(inherited) #{quote_array(value)}"
          else
            raise ArgumentError, "#{key} is not a plural setting, cannot have #{value.inspect} as its value" unless value.is_a? String
          end

          [key, value]
        end.to_h
      end

      def quote_array(array, prefix: nil)
        array.map do |element|
          case element
          when /\A([\w-]+?)=(.+)\z/
            key, value = $1, $2
            value = %("#{value}") if value =~ /[^\w\d]/
            %(#{key}=#{value})
          when /[\$\[\]\ ]/
            %("#{element}")
          else
            element
          end
        end.join(' ')
      end

      class Pod < BuildSettings
        def self.build_settings_names
          (@build_settings_names ||= []).concat(BuildSettings.build_settings_names)
        end

        def self.add_to_import_if_test(method_name)
          method = instance_method(method_name)
          define_method(method_name) do
            res = method.bind(self).call
            res = public_send("#{method_name}_to_import") + res if test_xcconfig?
            res
          end
        end

        def initialize(target, test_xcconfig)
          super(target)
          @test_xcconfig = test_xcconfig
        end

        def __clear__
          super
          dependent_targets.each { |pt| pt.build_settings.__clear__ }
        end

        def test_xcconfig?; @test_xcconfig; end

        def swift_active_compilation_conditions
          []
        end

        memoized add_to_import_if_test def frameworks
          return [] if (!target.requires_frameworks? || target.static_framework?) && !test_xcconfig?

          frameworks = vendored_dynamic_frameworks.map {|l| File.basename(l, '.framework') }
          frameworks.concat spec_consumers.flat_map(&:frameworks)
          frameworks.concat dependent_targets.flat_map { |pt| pt.build_settings.dynamic_frameworks_to_import }
          frameworks.concat dependent_targets.flat_map { |pt| pt.build_settings.static_frameworks_to_import } if test_xcconfig?
          frameworks.tap(&:uniq!).tap(&:sort!)
        end

        memoized def static_frameworks_to_import
          static_frameworks_to_import = vendored_static_frameworks.map { |f| File.basename(f, '.framework') }
          static_frameworks_to_import << target.product_basename if target.should_build? && target.requires_frameworks? && target.static_framework?
          static_frameworks_to_import
        end

        memoized def dynamic_frameworks_to_import
          dynamic_frameworks_to_import = vendored_dynamic_frameworks.map { |f| File.basename(f, '.framework') }
          dynamic_frameworks_to_import << target.product_basename if target.should_build? && target.requires_frameworks? && !target.static_framework?
          dynamic_frameworks_to_import.concat spec_consumers.flat_map(&:frameworks)
          dynamic_frameworks_to_import
        end

        memoized def weak_frameworks
          return [] if (!target.requires_frameworks? || target.static_framework?) && !test_xcconfig?

          weak_frameworks = spec_consumers.flat_map(&:weak_frameworks)
          weak_frameworks.concat dependent_targets.flat_map { |pt| pt.build_settings.weak_frameworks_to_import }
          weak_frameworks.tap(&:uniq!).tap(&:sort!)
        end

        memoized add_to_import_if_test def libraries
          return [] if (!target.requires_frameworks? || target.static_framework?) && !test_xcconfig?

          libraries = vendored_dynamic_libraries.map { |l| File.basename(l, l.extname).sub(/\Alib/, '') }
          libraries.concat spec_consumers.flat_map(&:libraries)
          libraries.concat dependent_targets.flat_map { |pt| pt.build_settings.dynamic_libraries_to_import }
          libraries.concat dependent_targets.flat_map { |pt| pt.build_settings.static_libraries_to_import } if test_xcconfig?
          libraries.tap(&:uniq!).tap(&:sort!)
        end

        memoized def static_libraries_to_import
          static_libraries_to_import = vendored_static_libraries.map { |l| File.basename(l, l.extname).sub(/\Alib/, '') }
          static_libraries_to_import << target.product_basename if target.should_build? && !target.requires_frameworks?
          static_libraries_to_import
        end

        memoized def dynamic_libraries_to_import
          vendored_dynamic_libraries.map { |l| File.basename(l, l.extname).sub(/\Alib/, '') } +
            spec_consumers.flat_map(&:libraries)
        end

        memoized def module_map_files
          dependent_targets.map {|t| t.build_settings.module_map_file_to_import }.compact.sort
        end

        memoized def module_map_file_to_import
          return if target.requires_frameworks?
          return unless target.defines_module?

          if target.uses_swift?
            # for swift, we have a custom build phase that copies in the module map, appending the .Swift module
            "${PODS_CONFIGURATION_BUILD_DIR}/#{target.label}/#{target.product_module_name}.modulemap"
          else
            "${PODS_ROOT}/#{target.module_map_path.relative_path_from(target.sandbox.root)}"
          end
        end

        memoized def spec_consumers
          target.spec_consumers.select {|c| c.spec.test_specification? == test_xcconfig? }
        end

        build_setting def pods_root
          '${SRCROOT}'
        end

        memoized def libraries_to_import
          static_libraries_to_import + dynamic_libraries_to_import
        end

        memoized def frameworks_to_import
          static_frameworks_to_import + dynamic_frameworks_to_import
        end

        memoized def weak_frameworks_to_import
          []
        end

        memoized def header_search_paths
          target.header_search_paths(test_xcconfig?).sort
        end

        memoized def xcconfig
          super.merge(pod_target_xcconfig)
        end

        memoized build_setting def library_search_paths
          vendored = vendored_dynamic_library_search_paths
          vendored.concat dependent_targets.flat_map { |t| t.build_settings.vendored_dynamic_library_search_paths }
          if test_xcconfig?
            vendored.concat dependent_targets.flat_map { |t| t.build_settings.library_search_paths_to_import }
            vendored.concat library_search_paths_to_import
          else
            vendored.delete(target.configuration_build_dir(CONFIGURATION_BUILD_DIR_VARIABLE))
          end
          vendored.tap(&:sort!).tap(&:uniq!)
        end

        memoized def vendored_static_libraries
          file_accessors.flat_map(&:vendored_static_libraries)
        end

        memoized def vendored_dynamic_libraries
          file_accessors.flat_map(&:vendored_dynamic_libraries)
        end

        memoized def vendored_static_frameworks
          file_accessors.flat_map(&:vendored_static_frameworks)
        end

        memoized def vendored_dynamic_frameworks
          file_accessors.flat_map(&:vendored_dynamic_frameworks)
        end

        memoized def vendored_static_library_search_paths
          vendored_static_libraries.map {|f| File.join '${PODS_ROOT}', f.dirname.relative_path_from(target.sandbox.root) }
        end

        memoized def vendored_dynamic_library_search_paths
          vendored_dynamic_libraries.map {|f| File.join '${PODS_ROOT}', f.dirname.relative_path_from(target.sandbox.root) }
        end

        memoized def library_search_paths_to_import
          vendored_library_search_paths = vendored_static_library_search_paths  + vendored_dynamic_library_search_paths
          return vendored_library_search_paths unless !target.requires_frameworks? && target.should_build?

          vendored_library_search_paths << target.configuration_build_dir(CONFIGURATION_BUILD_DIR_VARIABLE)
        end

        memoized build_setting def framework_search_paths
          paths = super
          paths.concat dependent_targets.flat_map { |t| t.build_settings.framework_search_paths_to_import }
          if test_xcconfig?
            paths.concat framework_search_paths_to_import
          else
            paths.delete(target.configuration_build_dir(CONFIGURATION_BUILD_DIR_VARIABLE))
          end
          paths.concat vendored_framework_search_paths
          paths.tap(&:sort!).tap(&:uniq!)
        end

        memoized def vendored_framework_search_paths
          file_accessors.flat_map(&:vendored_frameworks).map {|f| File.join '${PODS_ROOT}', f.dirname.relative_path_from(target.sandbox.root) }
        end

        memoized def framework_search_paths_to_import
          return vendored_framework_search_paths unless target.requires_frameworks? && target.should_build?

          vendored_framework_search_paths + [target.configuration_build_dir(CONFIGURATION_BUILD_DIR_VARIABLE)]
        end

        memoized build_setting def other_swift_flags
          return unless target.uses_swift?
          flags = super
          flags << '-suppress-warnings' if target.inhibit_warnings?
          if !target.requires_frameworks? && target.defines_module? && !test_xcconfig?
            flags.concat %w[ -import-underlying-module -Xcc -fmodule-map-file=${SRCROOT}/${MODULEMAP_FILE} ]
          end
          flags
        end

        memoized build_setting def swift_include_paths
          dependent_targets.flat_map {|t| t.build_settings.swift_include_paths_to_import }
        end

        memoized def swift_include_paths_to_import
          return [] unless target.uses_swift? && !target.requires_frameworks?

          [target.configuration_build_dir(CONFIGURATION_BUILD_DIR_VARIABLE)]
        end

        build_setting def pods_target_srcroot
          target.pod_target_srcroot
        end

        build_setting def skip_install
          'YES'
        end

        def requires_objc_linker_flag?
          test_xcconfig?
        end

        memoized def requires_fobjc_arc?
          target.podfile.set_arc_compatibility_flag? &&
            file_accessors.any? { |fa| fa.spec_consumer.requires_arc? }
        end

        build_setting def product_bundle_identifier
          'org.cocoapods.${PRODUCT_NAME:rfc1034identifier}'
        end

        memoized build_setting def configuration_build_dir
          return if test_xcconfig?
          target.configuration_build_dir(CONFIGURATION_BUILD_DIR_VARIABLE)
        end

        memoized def dependent_targets
          if test_xcconfig?
            target.all_dependent_targets
          else
            target.recursive_dependent_targets
          end
        end

        memoized def pod_target_xcconfig
          config = {}

          spec_consumers.each do |consumer|
            config.update(consumer.pod_target_xcconfig) # TODO resolve conflicts
          end

          config
        end

        memoized def file_accessors
          target.file_accessors.select {|fa| fa.spec.test_specification? == test_xcconfig? }
        end

        memoized build_setting def ld_runpath_search_paths
          return unless test_xcconfig?
          _ld_runpath_search_paths(test_bundle: true)
        end
      end

      class Aggregate < BuildSettings

        def self.build_settings_names
          @build_settings_names.concat(BuildSettings.build_settings_names)
        end

        attr_reader :configuration_name

        def initialize(target, configuration_name)
          super(target)
          @configuration_name = configuration_name
        end

        def self.from_pod_targets(setting)
          define_method(setting) do
            value = pod_targets.flat_map do |pod_target|
              settings = pod_target.build_settings
              settings.public_send("#{setting}_to_import") + settings.public_send(setting) # TODO only use _to_import
            end
            value.map!(&:to_s)
            value.uniq!
            value.sort!

            value
          end
          memoized(setting)
        end

        def self.from_search_paths_aggregate_targets(setting)
          method = instance_method(setting)
          define_method(setting) do
            value = method.bind(self).call
            value += target.search_paths_aggregate_targets.flat_map do |aggregate_target|
              build_settings = aggregate_target.build_settings(configuration_name) || raise("#{aggregate_target.inspect} has no build settings for configuration #{configuration_name.inspect}")
              build_settings.send(setting)
            end
            value.uniq.sort
          end
          memoized(setting)
        end

        memoized def xcconfig
          super.merge(merged_user_target_xcconfigs)
        end

        def __clear__
          super
          pod_targets.each { |pt| pt.build_settings.__clear__ }
          target.search_paths_aggregate_targets.each { |at| at.build_settings(configuration_name).__clear__ }
        end

        from_pod_targets :libraries

        from_search_paths_aggregate_targets from_pod_targets :library_search_paths

        from_search_paths_aggregate_targets from_pod_targets :frameworks
        from_search_paths_aggregate_targets from_pod_targets :weak_frameworks

        build_setting from_search_paths_aggregate_targets from_pod_targets :framework_search_paths

        from_search_paths_aggregate_targets from_pod_targets :swift_include_paths

        from_search_paths_aggregate_targets def header_search_paths
          if target.requires_frameworks?
            if pod_targets.all?(&:should_build?)
              []
            else
              target.sandbox.public_headers.search_paths(target.platform)
            end
          else
            target.sandbox.public_headers.search_paths(target.platform)
          end
        end

        memoized build_setting def pods_podfile_dir_path
          target.podfile_dir_relative_path
        end

        memoized def other_cflags
          super +
            header_search_paths.flat_map {|p| ['-isystem', p] } +
            framework_header_paths_for_iquote.flat_map {|p| ['-iquote', p] }
        end

        from_search_paths_aggregate_targets def framework_header_paths_for_iquote
          pod_targets.
            select {|pt| pt.should_build? && pt.requires_frameworks? }.
            map {|pt| "#{pt.build_product_path}/Headers" }
        end

        memoized build_setting def pods_root
          target.relative_pods_root
        end

        memoized build_setting def ld_runpath_search_paths
          return unless target.requires_frameworks? || vendored_dynamic_artifacts.any?
          symbol_type = target.user_targets.map(&:symbol_type).uniq.first
          test_bundle = symbol_type == :octest_bundle || symbol_type == :unit_test_bundle || symbol_type == :ui_test_bundle
          _ld_runpath_search_paths(requires_host_target: target.requires_host_target?, test_bundle: test_bundle)
        end

        memoized def vendored_dynamic_artifacts
          pod_targets.flat_map(&:file_accessors).flat_map(&:vendored_dynamic_artifacts)
        end

        memoized def requires_objc_linker_flag?
          includes_static_libs = !target.requires_frameworks?
          includes_static_libs ||= pod_targets.flat_map(&:file_accessors).any? { |fa| !fa.vendored_static_artifacts.empty? }
        end

        memoized def requires_fobjc_arc?
          target.podfile.set_arc_compatibility_flag? &&
            target.spec_consumers.any?(&:requires_arc?)
        end

        from_search_paths_aggregate_targets memoized def module_map_files
          pod_targets.map {|t| t.build_settings.module_map_file_to_import }.compact.sort
        end

        memoized build_setting def always_embed_swift_standard_libraries
          return unless must_embed_swift?
          return if target_swift_version < EMBED_STANDARD_LIBRARIES_MINIMUM_VERSION

          'YES'
        end

        memoized build_setting def embedded_content_contains_swift
          return unless must_embed_swift?
          return if target_swift_version >= EMBED_STANDARD_LIBRARIES_MINIMUM_VERSION

          'YES'
        end

        memoized def must_embed_swift?
          !target.requires_host_target? && pod_targets.any?(&:uses_swift?)
        end

        # !@group Private Helpers

        # @return [Version] the SWIFT_VERSION of the target being integrated
        #
        memoized def target_swift_version
          swift_version = target.target_definition.swift_version
          swift_version = nil if swift_version.blank?
          Version.new(swift_version)
        end

        EMBED_STANDARD_LIBRARIES_MINIMUM_VERSION = Version.new('2.3')

        # Returns the {PodTarget}s which are active for the current
        # configuration name.
        #
        # @return [Array<PodTarget>]
        #
        memoized def pod_targets
          target.pod_targets_for_build_configuration(configuration_name)
        end

        # Returns the +user_target_xcconfig+ for all pod targets and their spec
        # consumers grouped by keys
        #
        # @return [Hash{String,Hash{Target,String}]
        #
        def user_target_xcconfig_values_by_consumer_by_key
          pod_targets.each_with_object({}) do |target, hash|
            target.spec_consumers.each do |spec_consumer|
              spec_consumer.user_target_xcconfig.each do |k, v|
                (hash[k] ||= {})[spec_consumer] = v
              end
            end
          end
        end

        # Merges the +user_target_xcconfig+ for all pod targets into the
        # #xcconfig and warns on conflicting definitions.
        #
        # @return [Hash{String, String}]
        #
        memoized def merged_user_target_xcconfigs
          settings = user_target_xcconfig_values_by_consumer_by_key
          settings.each_with_object({}) do |(key, values_by_consumer), xcconfig|
            uniq_values = values_by_consumer.values.uniq
            values_are_bools = uniq_values.all? { |v| v =~ /^(yes|no)$/i }
            if values_are_bools
              # Boolean build settings
              if uniq_values.count > 1
                UI.warn 'Can\'t merge user_target_xcconfig for pod targets: ' \
                  "#{values_by_consumer.keys.map(&:name)}. Boolean build "\
                  "setting #{key} has different values."
              else
                xcconfig[key] = uniq_values.first
              end
            elsif PLURAL_SETTINGS.include? key
              # Plural build settings
              xcconfig[key] = uniq_values.join(' ')
            else
              # Singular build settings
              if uniq_values.count > 1
                UI.warn 'Can\'t merge user_target_xcconfig for pod targets: ' \
                  "#{values_by_consumer.keys.map(&:name)}. Singular build "\
                  "setting #{key} has different values."
              else
                xcconfig[key] = uniq_values.first
              end
            end
          end
        end
      end
    end
  end
end
