# encoding: UTF-8

require 'astroboa-cli/command/base'
require 'rbconfig'

# setup astroboa as a system service (daemon) that automatically starts on boot
class AstroboaCLI::Command::Service < AstroboaCLI::Command::Base

  LAUNCHD_CONFIG = '/Library/LaunchDaemons/com.betaconcept.astroboa.plist'
  
  # service:setup
  #
  # Setups astroboa as a system service (daemon). 
  # It requires that you have already installed astroboa using 'astroboa-cli server:install'.
  # Astroboa service will automatically start on system boot. 
  #
  # To start and stop astroboa when it is installed as a system service use 'astroboa-cli service:start' and 'astroboa-cli service:stop'
  #
  # IMPORTANT NOTICE:
  # When astroboa runs as a service the internallly installed JRUBY version and GEMS are used instead of the JRUBY used to run astroboa-cli.
  # When astroboa is started through 'server:start' command, the same JRUBY version and GEMS used by astroboa-cli will be used.
  # This behaviour shields the production server from the ruby setup that the astroboa-cli user might have and even allows to test newer ruby versions and gems
  # during development (run astroboa with server:start) and use more stable ones during production (setup astroboa as a service and run it through service:start).
  #
  # In MAC OS X astroboa is setup as a system launchd daemon.
  # Therefore, you must be authorized to use 'sudo' in order to use the 'service:setup' command.
  # If you want to disable astroboa service from automatically running on each boot then change the 'RunAtLoad' key to 'false' in '/Library/LaunchDaemons/com.betaconcept.astroboa.plist'
  #
  # In linux astroboa is setup as an upstart service (requires ubuntu or debian or a linux distro that supports upstart)
  #
  def setup
    error "Astroboa is running. Please first stop astoboa using 'astroboa-cli server:stop' and run the command again" if astroboa_running?
    install_launchd_service if mac_os_x?
    install_upstart_service if linux?
    display "We do not yet support installing astroboa as a service in windows" if windows?
  end
  
  # service:unset
  #
  # unsets astroboa from being a system service (daemon). 
  #
  # In MAC OS X it will unload astroboa from launchd and then remove astroboa from the list of system daemons (those that are loaded everytime the system boots).
  #
  # In LINUX it will unconfigure astroboa as an upstart service
  #
  def unset
    error "Astroboa is running. Please first stop astoboa using 'astroboa-cli service:stop' and run the command again" if astroboa_running?
    unset_launchd_service if mac_os_x?
    unset_upstart_service if linux?
    display "We do not yet support installing astroboa as a service in windows" if windows?
  end
  
  
  # service:start
  #
  # Starts astroboa service
  #
  # To install astroboa as a system service you should run 'astroboa-cli service:setup'
  #
  # In MAC OS X you may also start the service by running: 'launchctl start com.betaconcept.astroboa'
  #
  # In Linux you may also start the service by running: 'service astroboa start'
  #
  def start
    error "Astroboa is already running" if astroboa_running?
    start_launchd_service if mac_os_x?
  end
  
  # service:stop
  #
  # Stops astroboa service
  #
  # To setup astroboa as a system service you should run 'astroboa-cli service:setup'
  # 
  # In MAC OS X you may also stop the service by running: 'launchctl unload /Library/LaunchDaemons/com.betaconcept.astroboa.plist'
  # DO NOT use 'launchctl stop com.betaconcept.astroboa' because launchd will keep restarting the service.
  # If you use 'launchctl unload /Library/LaunchDaemons/com.betaconcept.astroboa.plist' to stop the service then you may restart it by using 
  # astroboa-cli service:start or run 'launchctl load /Library/LaunchDaemons/com.betaconcept.astroboa.plist' and then 'launchctl start com.betaconcept.astroboa'
  # In any case we recommend to use the commands provided by astroboa-cli that do all the necessary checks and remove the launchd complexity! 
  # 
  # In Linux you may also stop the service by running: 'service astroboa stop'
  #
  def stop
    error "Astroboa is not running" unless astroboa_running?
    stop_launchd_service if mac_os_x?
  end
  
  # service:check
  #
  # checks if astroboa is setup as a system service and whether astroboa service is running
  #
  def check
    check_launchd_service if mac_os_x?
    display "We do not yet support checking the status of astroboa service in linux and windows" if windows? || linux?
  end

private

  def install_launchd_service
    server_configuration = get_server_configuration
    astroboa_dir = server_configuration['install_dir']
    temp_launchd_config = File.join(astroboa_dir, 'com.betaconcept.astroboa.plist')
    log_file = File.join(astroboa_dir, 'torquebox', 'jboss', 'standalone', 'log', 'server.log')
    
    unless launchd_service_configured?
      uid = File.stat(astroboa_dir).uid
      astroboa_user = Etc.getpwuid(uid).name
      launchd_config_template = File.join(astroboa_dir, 'astroboa-setup-templates', 'AstroboaDaemon.plist.template')
      context = {:astroboa_dir => astroboa_dir, :java_home => ENV['JAVA_HOME'], :jruby_home => File.join(server_configuration['install_dir'], 'torquebox', 'jruby'), :astroboa_user => astroboa_user}
      render_template_to_file(launchd_config_template, context, temp_launchd_config)
      error "Failed to copy launchd config file to #{LAUNCHD_CONFIG}" unless process_os_command "sudo cp #{temp_launchd_config} #{LAUNCHD_CONFIG}"
      error "Failed to remove temporary launchd config file #{temp_launchd_config}" unless process_os_command "rm #{temp_launchd_config}"
      display "Generating launchd config file '#{LAUNCHD_CONFIG}': OK"
    end
    
    unless launchd_service_loaded?
      load_launchd_service
      return
    end
    
    display "Astroboa service is already configured as a service. Use 'astroboa-cli service:check' to check the service status, use 'astroboa-cli service:start' and 'astroboa-cli service:stop' to start and stop astroboa service"
    # FileUtils.mkdir_p log_dir, :mode => 0755 unless File.exists? log_dir
  end
  
  def load_launchd_service
    error "Failed to load astroboa service to launchd" unless process_os_command "launchctl load #{LAUNCHD_CONFIG}"
    display "Load astroboa service to launchd: OK"
    display "Checking proper service load..."
    error "Failed to load astroboa as a service" unless launchd_service_loaded?
    display "astroboa service properly loaded: OK"
    display "astroboa service is now starting...You can check the log file with 'tail -f #{log_file}'"
    display "If you want to STOP THE SERVICE use 'astroboa-cli service:stop'. To START THE SERVICE again use 'astroboa-cli service:start'. "
    display "ATTENTION!!! astroboa service will automatically start every time your MAC starts."
    display "If you want to disable astroboa service from automatically running on each boot then change the 'RunAtLoad' key to false in '/Library/LaunchAgents/com.betaconcept.astroboa.plist'"
  end
  
  def launchd_service_configured?
    
    unless File.exist?(LAUNCHD_CONFIG)
      display "#{LAUNCHD_CONFIG} not installed"
      return false
    end
    
    display "launchd config script '#{LAUNCHD_CONFIG}': OK"
    return true
  end
  
  
  def launchd_service_loaded?
    unless system 'launchctl list | grep astroboa'
      display "Astroboa is not listed as a service in launchctl"
      return false
    end
    
    display "launchctl lists astroboa as a service: OK"
    return true
  end
  
  
  def check_launchd_service
    display launchd_service_configured? ? "Astroboa is configured as a system service" : 
      "Astroboa is not configured as a service. Run 'astroboa-cli service:setup' to configure Astroboa as MAC OS X service"
    
    display astroboa_running? ? 'Astroboa is running' : 'Astroboa is not running'
  end
  
  
  def start_launchd_service
    unless launchd_service_configured?
      output_with_bang "Astroboa is not yet setup as a system service. To setup up astroboa as a service use 'astroboa-cli service:setup'"
      output_with_bang "If you just want to start astoboa without setting it up as a service use 'astroboa-cli server:start'"
      exit
    end
    
    unless launchd_service_loaded?
      display "astroboa service is not loaded lets loaded first"
      load_launchd_service load_launchd_service
      
      # we return since service automatically starts when loaded
      return
    end 
    
    error "Failed to start astroboa service" unless process_os_command "launchctl start com.betaconcept.astroboa"
    display "Astroboa service has been started"
  end
  
  
  def stop_launchd_service
    # To stop the service through launchd we need to use 'launchctl unload'
    # we cannot use 'launchctl stop' because this will cause the service to be restarted again (this is due to keepalive settings in plist file)
    # if we use 'launchctl unload' we need to reload the plist file each time we want to start astroboa again.
    # To avoid all this we may stop astroboa directly through jboss-cli. This causes jboss to exit with status 0 and thus launchd does not restart it (see keepalive settings in plist file)
    # So service:stop becomes equivalent to server:stop in MAC OS X.
    # So even if astroboa is not a service we will stop it with service:stop but we do a check and inform the user to prefer server:stop if astroboa is not setup as a service
    
    unless launchd_service_configured?
      output_with_bang "We will try to stop astroboa but you should use this command to stop astroboa only if it is setup as a system service."
      output_with_bang "Astroboa is not yet setup as a system service. To setup up astroboa as a service use 'astroboa-cli service:setup'"
      output_with_bang "To stop astoboa when it is not setup as a service prefer to use 'astroboa-cli server:stop'"
    end
    
    AstroboaCLI::Command::Server.new().stop
    
  end
  
  def unset_launchd_service
    display "Checking that astroboa is setup as a system service..."
    error "Astroboa is not set as a system service" unless launchd_service_configured?
    
    display "Checking that astroboa service is loaded..."
    if launchd_service_loaded?
      display "Trying to unload..."
      error "Failed to unload astroboa service from launchd" unless process_os_command("launchctl unload #{LAUNCHD_CONFIG}") && ! launchd_service_loaded?
      display "Astroboa service has been unloaded from launchd"
    end
    
    display 'Trying to remove from system services...'
    error "Failed to remove launchd config file '#{LAUNCHD_CONFIG}'. Check that you have sudo permission and run the command again or manually remove the plist file." unless process_os_command "sudo rm #{LAUNCHD_CONFIG}"
    display "Astroboa has been removed from system services"
  end
    
  
end

