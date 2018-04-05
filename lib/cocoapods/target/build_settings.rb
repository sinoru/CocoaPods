module Pod
  class Target
    class BuildSettings
      PLURAL_SETTINGS = Set.new %w[
        FRAMEWORK_SEARCH_PATHS
        GCC_PREPROCESSOR_DEFINITIONS
        HEADER_SEARCH_PATHS
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

      memoized build_setting def framework_search_paths
        []
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

      build_setting def other_cflags
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

      memoized build_setting  def other_ldflags
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

      build_setting def other_swift_flags
        []
      end

      build_setting def pods_root
        ''
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

      build_setting def pods_configuration_build_dir
        '${PODS_BUILD_DIR}/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)'
      end

      memoized def xcconfig
        settings = add_inherited_to_plural(to_h)
        Xcodeproj::Config.new(settings)
      end

      def to_h
        self.class.build_settings_names.reduce({}) {|a, e| a[e] = send(e.downcase); a }
      end

      def add_inherited_to_plural(hash)
        hash.map do |key, value|
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
          if element =~ /[\$\[\]\ ]/
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

        def initialize(target, test_xcconfig)
          super(target)
          @test_xcconfig = test_xcconfig
        end

        def test_xcconfig?; @test_xcconfig; end

        def swift_active_compilation_conditions
          []
        end

        memoized def frameworks
          target.spec_consumers.flat_map(&:frameworks)
        end

        def pods_root
          '${SRCROOT}'
        end

        memoized def libraries_to_import
          if target.requires_frameworks?
            []
          else
            [target.product_basename]
          end
        end

        memoized def frameworks_to_import
          if target.requires_frameworks?
            [target.product_basename]
          else
            []
          end
        end

        memoized def header_search_paths
          if target.requires_frameworks?

          else
            target.header_search_paths
          end
        end

        memoized def library_search_paths_to_import
          if target.requires_frameworks?
            []
          else
            %W[ ${PODS_CONFIGURATION_BUILD_DIR}/#{target.product_basename} ]
          end
        end

        build_setting def pods_target_srcroot
          target.pod_target_srcroot
        end

        build_setting def skip_install
          'YES'
        end

        build_setting def product_bundle_identifier
          'org.cocoapods.${PRODUCT_NAME:rfc1034identifier}'
        end

        memoized build_setting def configuration_build_dir
          target.configuration_build_dir(CONFIGURATION_BUILD_DIR_VARIABLE)
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

        from_pod_targets :libraries

        from_pod_targets :library_search_paths

        from_pod_targets :frameworks

        memoized def header_search_paths
          if target.requires_frameworks?
          else
            target.sandbox.public_headers.search_paths(target.platform)
          end
        end

        memoized build_setting def pods_podfile_dir_path
          target.podfile_dir_relative_path
        end

        memoized def other_cflags
          header_search_paths.flat_map {|p| ['-isystem', p] }
        end

        memoized def pods_root
          target.relative_pods_root
        end

        memoized def requires_objc_linker_flag?
          includes_static_libs = !target.requires_frameworks?
          includes_static_libs ||= pod_targets.flat_map(&:file_accessors).any? { |fa| !fa.vendored_static_artifacts.empty? }
        end

        # !@group Private Helpers

        # Returns the {PodTarget}s which are active for the current
        # configuration name.
        #
        # @return [Array<PodTarget>]
        #
        def pod_targets
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
        def merged_user_target_xcconfigs
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
            elsif key =~ /S$/
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
