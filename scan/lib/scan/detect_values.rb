module Scan
  # This class detects all kinds of default values
  class DetectValues
    # This is needed as these are more complex default values
    # Returns the finished config object
    def self.set_additional_default_values
      config = Scan.config

      # First, try loading the Scanfile from the current directory
      config.load_configuration_file(Scan.scanfile_name)

      # Detect the project
      FastlaneCore::Project.detect_projects(config)
      Scan.project = FastlaneCore::Project.new(config)

      # Go into the project's folder, as there might be a Snapfile there
      Dir.chdir(File.expand_path("..", Scan.project.path)) do
        config.load_configuration_file(Scan.scanfile_name)
      end

      Scan.project.select_scheme

      default_device_ios if Scan.project.ios?
      default_device_tvos if Scan.project.tvos?
      detect_destination

      default_derived_data

      return config
    end

    def self.default_derived_data
      return unless Scan.config[:derived_data_path].to_s.empty?
      default_path = Scan.project.build_settings(key: "BUILT_PRODUCTS_DIR")
      # => /Users/.../Library/Developer/Xcode/DerivedData/app-bqrfaojicpsqnoglloisfftjhksc/Build/Products/Release-iphoneos
      # We got 3 folders up to point to ".../DerivedData/app-[random_chars]/"
      default_path = File.expand_path("../../..", default_path)
      UI.verbose("Detected derived data path '#{default_path}'")
      Scan.config[:derived_data_path] = default_path
    end

    def self.filter_simulators(simulators, deployment_target)
      # Filter out any simulators that are not the same major and minor version of our deployment target
      deployment_target_version = Gem::Version.new(deployment_target)
      simulators.select do |s|
        sim_version = Gem::Version.new(s.ios_version)
        (sim_version >= deployment_target_version)
      end
    end

    def self.default_device_ios
      devices = Scan.config[:devices] || Array(Scan.config[:device]) # important to use Array(nil) for when the value is nil
      found_devices = []
      xcode_target = Scan.project.build_settings(key: "IPHONEOS_DEPLOYMENT_TARGET")

      if devices.any?
        # Optionally, we only do this if the user specified a custom device or an array of devices
        devices.each do |device|
          lookup_device = device.to_s.strip
          has_version = lookup_device.include?(xcode_target) || lookup_device.include?('(')
          lookup_device = lookup_device.tr('()', '') # Remove parenthesis
          # Default to Xcode target version if no device version is specified.
          lookup_device = lookup_device + " " + xcode_target unless has_version

          found = FastlaneCore::DeviceManager.all('iOS').detect do |d|
            (d.name + " " + d.ios_version).include? lookup_device
          end

          if found
            found_devices.push(found)
          else
            UI.error("Ignoring '#{device}', couldn't find matching device")
          end
        end

        if found_devices.any?
          Scan.devices = found_devices
          return
        else
          UI.error("Couldn't find any matching device for '#{devices}' - falling back to default simulator")
        end
      end

      sims = FastlaneCore::DeviceManager.simulators('iOS')
      xcode_target = Scan.project.build_settings(key: "IPHONEOS_DEPLOYMENT_TARGET")

      sims = filter_simulators(sims, xcode_target)

      # An iPhone 5s is reasonable small and useful for tests
      found = sims.detect { |d| d.name == "iPhone 5s" }
      found ||= sims.first # anything is better than nothing

      if found
        Scan.devices = [found]
      else
        UI.user_error!("No simulators found on local machine")
      end
    end

    def self.default_device_tvos
      devices = Scan.config[:devices] || Array(Scan.config[:device]) # important to use Array(nil) for when the value is nil
      found_devices = []

      if devices.any?
        # Optionally, we only do this if the user specified a custom device or an array of devices
        devices.each do |device|
          lookup_device = device.to_s.strip.tr('()', '') # Remove parenthesis

          found = FastlaneCore::DeviceManager.all('tvOS').detect do |d|
            (d.name + " " + d.os_version).include? lookup_device
          end

          if found
            found_devices.push(found)
          else
            UI.error("Ignoring '#{device}', couldn't find matching device")
          end
        end

        if found_devices.any?
          Scan.devices = found_devices
          return
        else
          UI.error("Couldn't find any matching device for '#{devices}' - falling back to default simulator")
        end
      end

      sims = FastlaneCore::DeviceManager.simulators('tvOS')
      xcode_target = Scan.project.build_settings(key: "TVOS_DEPLOYMENT_TARGET")
      sims = filter_simulators(sims, xcode_target)

      # Apple TV 1080p is useful for tests
      found = sims.detect { |d| d.name == "Apple TV 1080p" }
      found ||= sims.first # anything is better than nothing

      if found
        Scan.devices = [found]
      else
        UI.user_error!("No TV simulators found on the local machine")
      end
    end

    def self.min_xcode8?
      Helper.xcode_version.split(".").first.to_i >= 8
    end

    # Is it an iOS, a tvOS or a macOS device?
    def self.detect_destination
      if Scan.config[:destination]
        UI.important("It's not recommended to set the `destination` value directly")
        UI.important("Instead use the other options available in `scan --help`")
        UI.important("Using your value '#{Scan.config[:destination]}' for now")
        UI.important("because I trust you know what you're doing...")
        return
      end

      # building up the destination now
      if Scan.project.ios?
        Scan.config[:destination] = Scan.devices.map { |d| self.destination("iOS", d) }
      elsif Scan.project.tvos?
        Scan.config[:destination] = Scan.devices.map { |d| self.destination("tvOS", d) }
      else
        Scan.config[:destination] = min_xcode8? ? [self.destination("macOS", nil)] : [self.destination("OS X", nil)]
      end
    end

    def self.destination(platform, device)
      destination = "platform=#{platform}"
      unless device.nil?
        if device.is_simulator
          destination += " Simulator"
        end
        destination += ",id=#{device.udid}"
      end

      return destination
    end
  end
end
