module Pod
  class Target
    class BuildSettings
      PLURAL_SETTINGS = Set.new %w[
        FRAMEWORK_SEARCH_PATHS
        GCC_PREPROCESSOR_DEFINITIONS
        HEADER_SEARCH_PATHS
        LD_RUNPATH_SEARCH_PATHS
        LIBRARY_SEARCH_PATHS
        OTHER_CFLAGS
        OTHER_LDFLAGS
        OTHER_SWIFT_FLAGS
        SWIFT_ACTIVE_COMPILATION_CONDITIONS
        SWIFT_INCLUDE_PATHS
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

      memoized build_setting def other_ldflags
        ld_flags = []
        ld_flags << '-ObjC' if requires_objc_linker_flag?
        if target.podfile.set_arc_compatibility_flag? &&
            target.spec_consumers.any?(&:requires_arc?)
          ld_flags << '-fobjc-arc'
        end
        libraries.each {|l| ld_flags << %(-l"#{l}") }
        frameworks.each {|f| ld_flags << '-framework' << %("#{f}") }
        ld_flags
      end

      memoized build_setting def other_swift_flags
        return unless target.uses_swift?
        %w[-D COCOAPODS] + module_map_files.flat_map {|f| ['-Xcc', "-fmodule-map-file=#{f}"] }
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

      def [](key)
        @settings[key]
      end

      def merge_setting(key, value)
        if PLURAL_SETTINGS.include?(key)
          @settings[key].concat Array(value)
        else
          raise ArgumentError, "#{key} is not plural" if value.is_a?(Array)
          @settings[key] = value
        end
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

        def test_xcconfig?; @test_xcconfig; end

        def swift_active_compilation_conditions
          []
        end

        memoized add_to_import_if_test def frameworks
          vendored = vendored_frameworks.map {|l| File.basename(l, '.framework') }
          vendored.concat spec_consumers.flat_map(&:frameworks)
          vendored.tap(&:uniq!).tap(&:sort!)
        end

        memoized add_to_import_if_test def libraries
          vendored = vendored_libraries.map {|l| File.basename(l, l.extname).sub(/\Alib/, '') }
          vendored.concat spec_consumers.flat_map(&:libraries)
          vendored.tap(&:uniq!).tap(&:sort!)
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
          if !target.requires_frameworks? && target.should_build?
            [target.product_basename]
          else
            []
          end
        end

        memoized def frameworks_to_import
          if target.requires_frameworks? && target.should_build?
            [target.product_basename]
          else
            []
          end
        end

        memoized def header_search_paths
          if target.requires_frameworks? && !test_xcconfig?
            []
          else
            target.header_search_paths
          end
        end

        memoized def xcconfig
          super.merge(pod_target_xcconfig)
        end

        memoized build_setting def library_search_paths
          vendored = vendored_libraries.map {|f| File.join '${PODS_ROOT}', f.dirname.relative_path_from(target.sandbox.root) }
          vendored.concat dependent_targets.flat_map { |t| t.build_settings.library_search_paths_to_import }
          vendored.tap(&:sort!)
        end

        memoized def vendored_libraries
          file_accessors.flat_map(&:vendored_libraries)
        end

        memoized def vendored_frameworks
          file_accessors.flat_map(&:vendored_frameworks)
        end

        memoized def library_search_paths_to_import
          return [] unless !target.requires_frameworks? && target.should_build?

          [target.configuration_build_dir(CONFIGURATION_BUILD_DIR_VARIABLE)]
        end

        memoized build_setting def framework_search_paths
          paths = dependent_targets.flat_map { |t| t.build_settings.framework_search_paths_to_import }
          paths.concat file_accessors.flat_map(&:vendored_frameworks).map {|f| File.join '${PODS_ROOT}', f.dirname.relative_path_from(target.sandbox.root) }
          paths.unshift "$(PLATFORM_DIR)/Developer/Library/Frameworks" if test_xcconfig? || frameworks.include?("XCTest") || frameworks.include?("SenTestingKit")
          paths.tap(&:sort!)
        end

        memoized def framework_search_paths_to_import
          return [] unless target.requires_frameworks? && target.should_build?

          [target.configuration_build_dir(CONFIGURATION_BUILD_DIR_VARIABLE)]
        end

        memoized build_setting def other_swift_flags
          return unless target.uses_swift?
          super +
            if !target.requires_frameworks? && target.defines_module? && !test_xcconfig?
              %w[ -import-underlying-module -Xcc -fmodule-map-file=${SRCROOT}/${MODULEMAP_FILE} ]
            else
              []
            end
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

        build_setting def product_bundle_identifier
          'org.cocoapods.${PRODUCT_NAME:rfc1034identifier}'
        end

        memoized build_setting def configuration_build_dir
          return if test_xcconfig?
          target.configuration_build_dir(CONFIGURATION_BUILD_DIR_VARIABLE)
        end

        memoized def dependent_targets
          targets = target.dependent_targets
          targets += [target] if test_xcconfig?
          targets
        end

        memoized def pod_target_xcconfig
          config = {}

          spec_consumers.each do |consumer|
            config.update(consumer.pod_target_xcconfig)
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
            pod_targets.flat_map do |pod_target|
              settings = pod_target.build_settings
              settings.public_send("#{setting}_to_import") + settings.public_send(setting)
            end.uniq.sort
          end
          memoized(setting)
        end

        memoized def xcconfig
          super.merge(merged_user_target_xcconfigs)
        end

        from_pod_targets :libraries

        from_pod_targets :library_search_paths

        from_pod_targets :frameworks

        build_setting from_pod_targets :framework_search_paths

        from_pod_targets :swift_include_paths

        memoized def header_search_paths
          if target.requires_frameworks?
            # if pod_targets.all?(&:should_build?)
              []
            # else
            #   target.sandbox.public_headers.search_paths(target.platform)
            # end
          else
            target.sandbox.public_headers.search_paths(target.platform)
          end
        end

        memoized build_setting def pods_podfile_dir_path
          target.podfile_dir_relative_path
        end

        memoized def other_cflags
          super + header_search_paths.flat_map {|p| ['-isystem', p] } +
            pod_targets.select {|pt| pt.should_build? && pt.requires_frameworks? }.flat_map do |target|
              ['-iquote', "#{target.build_product_path}/Headers"]
            end
        end

        memoized build_setting def pods_root
          target.relative_pods_root
        end

        memoized build_setting def ld_runpath_search_paths
          return unless target.requires_frameworks? || vendored_dynamic_artifacts.any?
          _ld_runpath_search_paths(requires_host_target: target.requires_host_target?)
        end

        memoized def vendored_dynamic_artifacts
          pod_targets.flat_map(&:file_accessors).flat_map(&:vendored_dynamic_artifacts)
        end

        memoized def requires_objc_linker_flag?
          includes_static_libs = !target.requires_frameworks?
          includes_static_libs ||= pod_targets.flat_map(&:file_accessors).any? { |fa| !fa.vendored_static_artifacts.empty? }
        end

        memoized def module_map_files
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
          Version.new target.target_definition.swift_version unless target.target_definition.swift_version.blank?
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
