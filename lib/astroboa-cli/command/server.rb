# encoding: utf-8

require 'astroboa-cli/command/base'
require 'astroboa-cli/command/repository'
require 'fileutils'
require 'rbconfig'
require 'progressbar'
require 'net/http'
require 'uri'
require 'yaml'
  
# install and setup astroboa server
#
class AstroboaCLI::Command::Server < AstroboaCLI::Command::Base
  
  # server:install
  #
  # Installs and setups astroboa server.
  # Use the install command only for the initial installation. If you want to upgrade see 'astroboa-cli help server:upgrade'
  # Before you run the install command check the following requirements: 
  # + You should have already installed java 1.6 and ruby 1.9.x
  # + You are running this command from ruby version 1.9.x or later
  # + You should have the unzip command. It is required for unzipping the downloaded packages
  # + If you choose a database other than derby then the database should be already installed and running and you should know the db admin account password
  #
  # -i, --install_dir INSTALLATION_DIRECTORY    # The full path to the directory into which to install astroboa # Default is '/opt/astroboa' in linux and '$HOME/astroboa' in mac os x and windows
  # -r, --repo_dir REPOSITORIES_DIRECTORY       # The full path of the directory that will contain the repositories configuration and data # Default is $installation_dir/repositories
  # -d, --database DATABASE_VENDOR              # Select which database to use for data persistense # Supported databases are: derby, postgres-8.2, postgres-8.3, postgres-8.4, postgres-9.0, postgres-9.1 # Default is derby
  # -s, --database_server DATABASE_SERVER_IP    # Specify the database server ip or FQDN (e.g 192.168.1.100 or postgres.localdomain.vpn) # Default is localhost # Not required if db is derby (it will be ignored)
  # -u, --database_admin DB_ADMIN_USER          # The user name of the database administrator # If not specified it will default to 'postgres' for postgresql db # Not required if db is derby (it will be ignored) 
  # -p, --database_admin_password PASSWORD      # The password of the database administrator # Defaults to empty string # Not required if database is derby (it will be ignored)
  #
  def install
    @torquebox_download_url = 'http://www.astroboa.org/releases/astroboa/latest/torquebox-dist-2.0.3-bin.zip'
    @torquebox_package = @torquebox_download_url.split("/").last
    
    @torquebox_version_download_url = 'http://www.astroboa.org/releases/astroboa/latest/TORQUEBOX-VERSION'
    @torquebox_version_file = @torquebox_version_download_url.split("/").last
    
    @astroboa_ear_download_url = 'http://www.astroboa.org/releases/astroboa/latest/astroboa.ear'
    @astroboa_ear_package = @astroboa_ear_download_url.split("/").last
    
    @astroboa_setup_templates_download_url = 'http://www.astroboa.org/releases/astroboa/latest/astroboa-setup-templates.zip'
    @astroboa_setup_templates_package = @astroboa_setup_templates_download_url.split("/").last
    
    @schemas_download_url = 'http://www.astroboa.org/releases/astroboa/latest/schemas.zip'
    @schemas_package = @schemas_download_url.split("/").last
    
    @astroboa_version_download_url = 'http://www.astroboa.org/releases/astroboa/latest/ASTROBOA-VERSION'
    @astroboa_version_file = @astroboa_version_download_url.split("/").last
    
    @install_dir = options[:install_dir] ||= mac_os_x? || windows? ? File.join(Dir.home, 'astroboa') : '/opt/astroboa'
    @install_dir = File.expand_path @install_dir # if provided path was not absolute expand it
    @repo_dir = options[:repo_dir] ||= File.join(@install_dir, "repositories")
    @repo_dir = File.expand_path @repo_dir # if provided path was not absolute expand it
    display <<-MSG.gsub(/^ {4}/, '')
    Starting astroboa server installation 
    Server will be installed in: #{@install_dir} 
    Repository Data and config will be stored in: #{@repo_dir}
    MSG
    
    @database = options[:database] ||= 'derby'
    
    db_error_message =<<-MSG.gsub(/^ {4}/, '')
    The selected database '#{@database}' is not supported. 
    Supported databases are: derby, postgres-8.2, postgres-8.3, postgres-8.4, postgres-9.0, postgres-9.1
    MSG
    
    error db_error_message unless %W(derby postgres-8.2 postgres-8.3 postgres-8.4 postgres-9.0 postgres-9.1).include?(@database)
    
    if @database.split("-").first == "postgres"
      @database_admin = options[:database_admin] ||= "postgres"
      @database_admin_password = options[:database_admin_password] ||= ""
    else
      @database_admin = "sa"
      @database_admin_password = ""
    end
    @database_server = options[:database_server] ||= "localhost"
    display "repository database is '#{@database}' accessed with user: '#{@database_admin}'"
    display "Database server IP or FQDN is: #{@database_server}" if @database.split("-").first == "postgres"
    # check if all requirement are fulfilled before proceeding with the installation 
    check_installation_requirements
    download_server_components
    install_server_components
    save_server_configuration
    create_central_identity_repository
    set_astroboa_owner
    cleanup_installation
  #  export_environment_variables
  end
  
  
  # server:start
  #
  # starts astroboa server in the foreground or as a background process.
  #
  # If you start it as a foreground process you can stop it by using Ctrl+c
  # If you start is as a background process use 'astroboa-cli server:stop' to gracefully stop astroboa
  #
  # It is recommented to use this command only during development and install astroboa as a service in production systems.
  # If you install astroboa as a service it will be automatically started every time your system starts.
  #
  # To find how to install and start / stop astroboa as a service see:
  # 'astroboa-cli help service:install'
  # 'astroboa-cli help service:start'
  # 'astroboa-cli help service:stop'
  #
  # -b, --background                # Starts astroboa in the background. Use 'astroboa-cli server:stop' to gracefully stop it
  # -j, --jvm_options JVM_OPTIONS   # java options for starting the astroboa jvm 
  #
  def start
    error 'astroboa is already running' if astroboa_running?

    astroboa_installed?
    
    server_config = get_server_configuration
    
    # Astroboa runs inside torquebox (a special version of JBOSS AS 7) which requires jruby
    # Torquebox comes with the required jruby installed.
    # If the env variable 'JRUBY_HOME' exists torquebox does not use ts own jruby but that pointed by the env variable
    # So we unset the variable (just in case it is set) to enforce torquebox to use its own jruby
    ENV.delete('JRUBY_HOME')
    
    # set jruby opts so that jruby runs in 1.9 mode
    ENV['JRUBY_OPTS'] = '--1.9'
    
    # don't send the gemfile from the current app
    ENV.delete('BUNDLE_GEMFILE')
    
    # append java options to the environment variable
    ENV['APPEND_JAVA_OPTS'] = options[:jvm_options]
    
    command = File.join(server_config['install_dir'], 'torquebox', 'jboss', 'bin', 'standalone.sh')
    
    
    jboss_log_file = File.join(server_config['install_dir'], 'torquebox', 'jboss', 'standalone', 'log', 'server.log')
    
    # We should always run astroboa as the user that owns the astroboa installation
    # otherwise problems with file permissions may be encountered.
    # If the current process owner is not the astroboa owner then we check if process owner 
    # is the super user (i.e astroboa-cli is run with sudo).
    # If process owner is super user we change the process owner 
    # to be the astroboa user (we can do that since process run with sudo privileges) and we run astroboa.
    # If process owner is not super user we give a notice that astroboa-cli should be executed with sudo and exit. 
    user = ENV['USER'] if mac_os_x? || linux?
    user = ENV['USERNAME'] if windows?
    install_dir = server_config['install_dir']
    astroboa_uid = File.stat(install_dir).uid
    astroboa_user = Etc.getpwuid(astroboa_uid).name
    process_uid = Process.uid
    process_user = Etc.getpwuid(process_uid).name
    
    if astroboa_uid != process_uid
      display "You are running astroboa-cli as user: #{process_user} and astroboa should run as user: #{astroboa_user}"
      display "We need sudo privileges in order to do this. Lets check..."
      if process_uid != 0
        error <<-MSG.gsub(/^ {8}/, '')
        You are not running with sudo privileges. Please run astroboa-cli with sudo
        If you installed ruby with rbenv you need to install 'rbenv-sudo' plugin and then run 'rbenv sudo astroboa-cli server:start'
        For 'rbenv-sudo' check ruby installation instructions at https://github.com/betaconcept/astroboa-cli
        MSG
      else
        Process::UID.change_privilege(astroboa_uid)
        display "Running with sudo: OK" if user != 'root'
        display "You are root: OK" if user == 'root'
      end
    end
        
    if options[:background]
      display "Astroboa is starting in the background..."
      display "You can check the log file with 'tail -f #{jboss_log_file}'"
      display "When server startup has finished access astroboa console at: http://localhost:8080/console"
      exec %(#{command} > /dev/null 2>&1 &)
      #exec %(#{command} &), :pgroup => true, [:in, :out, :err] => '/dev/null'
    else
      display "Astroboa is starting in the foreground..."
      display "When server startup has finished access astroboa console at: http://localhost:8080/console"
      exec %(#{command})
    end
    
  end
  
  # server:stop
  #
  # stops astroboa server if it is already running.
  # It is recommented to use this command only during development and install astroboa as a service in production systems.
  # To find how to install and start / stop astroboa as a service see:
  # 'astroboa-cli help service:install'
  # 'astroboa-cli help service:start'
  # 'astroboa-cli help service:stop'
  #
  def stop
    error 'Astroboa is not running' unless astroboa_running?
    server_config = get_server_configuration
    jboss_cli_command = File.join(server_config['install_dir'], 'torquebox', 'jboss', 'bin', 'jboss-cli.sh')
    shutdown_command = "#{jboss_cli_command} --connect --command=:shutdown"
    output = `#{shutdown_command}` if mac_os_x?
    output = `su - astroboa -c "#{shutdown_command}"` if linux?
    command_status = $?.to_i
    if command_status == 0 && output =~ /success/
      display "Astroboa has been successfully stopped"
    else
      error "Failed to shutdown Astroboa. Message is: #{output}"
    end
    
  end
  
  # server:check
  #
  # checks if astroboa server is properly installed and displays the installation paths
  # It also displays if astroboa is running
  #
  def check
    astroboa_installed?
    display astroboa_running? ? 'astroboa is running' : 'astroboa is not running' 
  end
  
  
private
  
  def check_installation_requirements
    display "Checking installation requirements"
    
    # if OS is linux or [OS is mac and install_dir / repo_dir is not writable by current user] 
    # then astroboa-cli should run with sudo in order to have the required privileges to write files
    check_if_running_with_sudo if linux? || (mac_os_x? && !(dir_writable?(@install_dir) && dir_writable?(@repo_dir)))
    
    # do not proceed if astroboa is already installed
    check_if_astroboa_exists_in_install_dirs
    
    # installation is not currently supported on windows
    check_if_os_is_windows
    
    # check if the proper version of java is installed
    java_ok?
    
    # check if unzip command is available
    check_if_unzip_is_installed
    
    # check if 'pg' gem is installed if repositories will be backed by postgres
    error <<-MSG.gsub(/^ {4}/, '') if @database.split("-").first == "postgres" && !gem_available?('pg')
    You should manually install the 'pg' gem if you want to create repositories backed by postgres
    astroboa-cli gem does not automatically install 'pg' gem since in some environments (e.g. MAC OS X) this might require 
    to have a local postgres already installed, which in turn is too much if you do not care about postgres.
  	In *Ubuntu Linux* run first 'sudo apt-get install libpq-dev' and then run 'gem install pg'.
  	For MAC OS x read http://deveiate.org/code/pg/README-OS_X_rdoc.html to learn how to install the 'pg' gem.
    MSG
  end
  
  
  def check_if_os_is_windows
    message = "astroboa server installation is currently supported for linux and mac os x"
    error message if RbConfig::CONFIG['host_os'] =~ /mswin|windows|cygwin/i
    display "Checking if operating system is supported: OK"
  end
  
  
  def check_if_astroboa_exists_in_install_dirs
    astroboa_error_message = "Astroboa seems to be already installed at #{@install_dir}. Delete the installation directory or specify another install path. Run 'astroboa-cli help server:upgrade' to find how to upgrade"
    repositories_error_message = "Repositories already exist at #{@repo_dir}. Specify another repository path or run 'astroboa-cli help server:upgrade' to find how to upgrade"
    error astroboa_error_message if File.directory? File.join(@install_dir, "torquebox")
    error repositories_error_message if File.directory? File.join(@repo_dir, "identities")
    display "Verifing that Astroboa is not already installed in the specified directories: OK"
  end
  
  
  def astroboa_installed?
    server_config = get_server_configuration
    
    problem_message = "Astroboa is not properly installed."
    
    astroboa_ear = Dir[File.join server_config['install_dir'], "torquebox", "jboss", "standalone", "deployments", "astroboa*.ear"].pop
    error "#{problem_message} Astroboa ear package is not installed" unless astroboa_ear
    display "Check astroboa ear : OK"
    
    error "#{problem_message} Astroboa identities repository is not setup" unless File.directory? File.join(server_config['repos_dir'], "identities")
    display "Check Astroboa identities repository : OK"
    
    # since the astroboa user is the same as the astroboa-cli user we can also check the environment variables
    # if mac_os_x?
    #       error "#{problem_message} Environment variable 'ASTROBOA_HOME' is not set. Check that your .bash_profile has run and it properly exports the 'ASTROBOA_HOME' environment variable" unless ENV['ASTROBOA_HOME']
    #       error "#{problem_message} Environment variable 'ASTROBOA_REPOSITORIES_HOME' is not set. Check that your .bash_profile has run and it properly exports the 'ASTROBOA_REPOSITORIES_HOME' environment variable" unless ENV['ASTROBOA_REPOSITORIES_HOME'] 
    #       error "#{problem_message} Environment variable 'JBOSS_HOME' is not set. Check that your .bash_profile has run and it properly exports the 'JBOSS_HOME' environment variable" unless ENV['JBOSS_HOME']
    #       display "Check existence of required environment variables : OK"
    #       
    #       display "Check consistency between environment variables and Astroboa Server Settings File #{get_server_conf_file} ", false
    #       error "#{problem_message} Missmatch of Astroboa installation dir in environmet variable 'ASTROBOA_HOME' (#{ENV['ASTROBOA_HOME']}) and server settings (#{server_config['install_dir']})" unless server_config['install_dir'] == ENV['ASTROBOA_HOME']
    #       error "#{problem_message} Missmatch of repositories dir in environmet variable 'ASTROBOA_REPOSITORIES_HOME' (#{ENV['ASTROBOA_REPOSITORIES_HOME']}) and server config settings (#{server_config['repos_dir']})" unless server_config['repos_dir'] == ENV['ASTROBOA_REPOSITORIES_HOME']
    #       error "#{problem_message} The mandatory repository 'identities' is not configured in server settings. Use the command 'repository:create identities' to create it." unless repository_in_server_config?(server_config, 'identities')
    #       display ": OK"
    #     end
    
    ok_message = "Astroboa installaion is ok.\nInstallation Path: #{server_config['install_dir']}\nRepository configuration and data are stored in: #{server_config['repos_dir']}"
    display ok_message
  end
  
  
  def java_ok?
    error('Please install java 6 (version 1.6.x) or java 7 (version 1.7.x) to proceed with installation') unless has_executable_with_version("java", "1\\.6|7", '-version')
  end
  
  
  def check_if_wget_is_installed
    error('Some files need to be downloaded. Please install \'wget\' and run the installation again') unless has_executable("wget")
  end
  
  
  def check_if_unzip_is_installed
    error('Some archives need to be unzipped. Please install \'unzip\' and run the installation again') unless has_executable("unzip")
  end
  
  
  def download_server_components
    # create installation directory
    begin
      FileUtils.mkdir_p @install_dir
    rescue SystemCallError => e
      error "Failed to create installation directory '#{@install_dir}' \n the Error is: #{e.message}"
    end
   
    display "Dowloading astroboa server components to #{@install_dir}"
    
    # download torquebox
    download_package(@torquebox_download_url, @install_dir) unless File.size?(File.join(@install_dir, @torquebox_package)) == 173153188
    
    # download torquebox version file
    download_package(@torquebox_version_download_url, @install_dir) unless File.size?(File.join(@install_dir, @torquebox_version_file)) == 6
    
    # download astroboa ear
    download_package(@astroboa_ear_download_url, @install_dir) unless File.size?(File.join(@install_dir, @astroboa_ear_package)) == 63783475
    
    # download astroboa version file
    download_package(@astroboa_version_download_url, @install_dir) unless File.size?(File.join(@install_dir, @astroboa_version_file)) == 15
    
    # download astroboa setup templates
    download_package(@astroboa_setup_templates_download_url, @install_dir) unless File.size?(File.join(@install_dir, @astroboa_setup_templates_package)) == 11030750
    
    # download astroboa schemas
    download_package(@schemas_download_url, @install_dir) unless File.size?(File.join(@install_dir, @schemas_download_url)) == 28426
  end
  
  
  def download_package_with_wget(package_url, install_dir)
    command = %(bash -c 'wget -c --directory-prefix=#{install_dir} #{package_url} 2>>#{log_file}')
    package = package_url.split('/').last
    log.info "Downloading #{package} with command: #{command}"
    display "Downloading #{package}"
    error "Failed to download package '#{package}'. Check logfile #{log_file}" unless process_os_command command
  end
  
  
  def download_package(package_url, install_dir)
    package_uri = URI.parse package_url
    package = package_url.split('/').last
    file = File.join install_dir, package
    display "Downloading #{package} from #{package_uri.host} to #{file}"
    
    Net::HTTP.start package_uri.host, package_uri.port do |http|
      bytesDownloaded = 0
      http.request Net::HTTP::Get.new(package_uri.path) do |response|
        pBar = ProgressBar.new package, 100
        size = response.content_length
        File.open(file,'w')  do |file|
          response.read_body do |segment|
            bytesDownloaded += segment.length
            if bytesDownloaded != 0
              percentDownloaded = (bytesDownloaded * 100) / size
              pBar.set(percentDownloaded)
            end
            file.write(segment)
          end
          pBar.finish
        end
      end
    end
    
    log.info "#{package} downloaded successfully"
  end
  
    
  def install_server_components
    create_astroboa_user
    display "Installing server components to #{@install_dir}"
    install_torquebox
    install_astroboa
  end
  
  
  def create_astroboa_user
    # in mac os x we do not create a separate user
    user = 'astroboa'
    if linux?
      display "Adding usergroup and user '#{user}'"
      command = "groupadd -f #{user} 2>>#{log_file}"
      error "Failed to create usergroup astroboa. Check logfile #{log_file}" unless process_os_command command
      command = "useradd -m -g #{user} #{user} 2>>#{log_file}"
      error "Failed to create user astroboa. Check logfile #{log_file}" unless process_os_command command
    end
  end
  
  
  def install_torquebox
    unzip_torquebox
    # we cannot use the ruby lib to unzip since it does not preserve file permissions
    #unzip_file(File.join(@install_dir, @torquebox_package), @install_dir)
    create_torquebox_symbolic_link
    
    # may be that we do not need this any more
    # add_torquebox_env_settings
  end
  
  
  def unzip_torquebox
    command = %(bash -c 'cd #{@install_dir} && #{extract_archive_command @torquebox_package} #{File.join(@install_dir, @torquebox_package)} 2>>#{log_file}')
    log.info "Installing torquebox with command: #{command}"
    error "Failed to install torquebox" unless process_os_command command
  end
  
  
  def create_torquebox_symbolic_link
    # create a symbolic link from the versioned directory to which torquebox was extracted (e.g. torquebox-2.0.cr1) to just 'torquebox'
    # we need this in order to create the required export paths once instead of recreating them each time torquebox is upgrated
    begin
      torquebox_dir = Dir["#{@install_dir}/torquebox*/"].pop
      display %(Adding symbolic link from #{torquebox_dir} to #{File.join(@install_dir, "torquebox")})
      FileUtils.ln_s "#{torquebox_dir}", File.join(@install_dir, "torquebox")
    rescue SystemCallError => e
      error %(Failed to create symbolic link from '#{File.join(@install_dir, torquebox_dir)}' to '#{File.join(@install_dir, "torquebox")}' \n the Error is: #{e.message})
    end
  end
  
  
  def add_torquebox_env_settings
    # add required environment settings to .bash_profile
    user_dir = File.expand_path("~astroboa") if linux?
    user_dir = ENV["HOME"] if mac_os_x?
    
    display "Adding required environment settings in #{user_dir}/.bash_profile"
    bash_profile_path = File.join(user_dir, ".bash_profile")
    settings_start_here_comment = '# ASTROBOA REQUIRED PATHS CONFIGURATION STARTS HERE'
    settings_end_here_comment = '# ASTROBOA REQUIRED PATHS CONFIGURATION ENDS HERE'
    # remove any previous settings
    delete_file_content_between_regex(bash_profile_path, settings_start_here_comment, settings_end_here_comment) if File.exists? bash_profile_path
    # write the new settings
    File.open(bash_profile_path, 'a+') do |f| 
      env_settings =<<SETTINGS

#{settings_start_here_comment}
export ASTROBOA_HOME=#{@install_dir}
export ASTROBOA_REPOSITORIES_HOME=#{@repo_dir}
export TORQUEBOX_HOME=$ASTROBOA_HOME/torquebox
export JBOSS_HOME=$TORQUEBOX_HOME/jboss
#{"export PATH=$JRUBY_HOME/bin:$PATH" if linux?}
#{settings_end_here_comment}
SETTINGS
      
      f.write env_settings
    end
  end
  
  
  def unzip_schemas
    unzip_file(File.join(@install_dir, @schemas_package), @install_dir)
  end
  
  
  def install_astroboa
    # unzip the templates first
    unzip_file(File.join(@install_dir, @astroboa_setup_templates_package), @install_dir)
    
    # unzip astroboa schemas that are used for user schema validation
    unzip_schemas
    
    jboss_dir = File.join(@install_dir, "torquebox", "jboss")
    jboss_modules_dir = File.join(jboss_dir, "modules")
    astroboa_setup_templates_dir = File.join(@install_dir, "astroboa-setup-templates")
    
    create_repo_dir
    
    install_astroboa_ear(jboss_dir)
    
    install_jdbc_modules(astroboa_setup_templates_dir, jboss_modules_dir)

    install_spring_modules(astroboa_setup_templates_dir, jboss_modules_dir)
    
    install_jboss_runtime_config(astroboa_setup_templates_dir, jboss_dir)
    
    install_jboss_config(astroboa_setup_templates_dir, jboss_dir)
    
  end
  
  
  def create_repo_dir
    # create directory for repository data and astroboa repositories configuration file
    begin
      FileUtils.mkdir_p @repo_dir
      display "Creating Repositories Directory: OK"
    rescue SystemCallError => e
      error "Failed to create repositories directory '#{@repo_dir}' \n the Error is: #{e.message}"
    end
  end
  
  
  def install_astroboa_ear(jboss_dir)
    FileUtils.cp File.join(@install_dir, @astroboa_ear_package), File.join(jboss_dir, "standalone", "deployments")
    display "Copying astroboa ear package into jboss deployments: OK"
  end
  
  
  def install_jdbc_modules(astroboa_setup_templates_dir, jboss_modules_dir)
    # copy both derby and postgres jdbc driver module
    # This is required since both derby and postgres modules have been specified as dependencies of astroboa.ear module
    FileUtils.cp_r File.join(astroboa_setup_templates_dir, "jdbc-drivers", "derby", "org"), jboss_modules_dir
    display "Copying derby jdbc driver module into jboss modules #{("(derby module is installed even if postgres has been selected)" unless @database == 'derby')}: OK"
    # copy postgres driver
    # if postgres has been specified in options then install the drivers for the specified version
    # else install drivers for postgres 9.1
    postgres_db = @database
    postgres_db = 'postgres-9.1' if @database == 'derby'
    FileUtils.cp_r File.join(astroboa_setup_templates_dir, "jdbc-drivers", postgres_db, "org"), jboss_modules_dir
    display %(Copying #{postgres_db} jdbc driver module into jboss modules #{("(postgres drivers are copied even if derby has been selected)" if @database == 'derby')}: OK)
  end
  
  
  def install_spring_modules(astroboa_setup_templates_dir, jboss_modules_dir)
    # copy spring and snowdrop modules to jboss modules
    FileUtils.cp_r File.join(astroboa_setup_templates_dir, "jboss-modules", "org"), jboss_modules_dir
    display "Copying spring and snowdrop modules into jboss modules: OK" 
  end
  
  
  def install_jboss_runtime_config(astroboa_setup_templates_dir, jboss_dir)
    # preserve original jboss runtime config and copy customized runtime config into jboss bin directory
    original_runtime_config = File.join(jboss_dir, "bin", "standalone.conf")
    FileUtils.cp original_runtime_config, "#{original_runtime_config}.original"
    FileUtils.cp File.join(astroboa_setup_templates_dir, "standalone.conf"), original_runtime_config
    display "Copying jboss runtime config into jboss bin: OK" 
  end
  
  
  def install_jboss_config(astroboa_setup_templates_dir, jboss_dir)
    # create jboss config from template and write it to jboss standalone configuration directory, preserving the original file
    original_jboss_config = File.join(jboss_dir, "standalone", "configuration", "standalone.xml")
    FileUtils.cp original_jboss_config, "#{original_jboss_config}.original"
    jboss_config_template = File.join(astroboa_setup_templates_dir, "standalone.xml")
    context = {:astroboa_config_dir => @repo_dir}
    render_template_to_file(jboss_config_template, context, original_jboss_config)
    display "Generating and copying jboss config into jboss standalone configuration directory: OK"
  end
  
  
  # currently not used - consider to remove
  def create_pgpass_file
    if @database.split("-").first == "postgres"
      pgpass_file = File.expand_path(File.join("~",".pgpass"))
      pgpass_file = File.expand_path(File.join("~astroboa",".pgpass")) unless RbConfig::CONFIG['host_os'] =~ /darwin/i
      
      pgpass_config = "localhost:5432:*:#{@database_admin}:#{@database_admin_password}"
    
      File.open(pgpass_file,"w") do |f|
        f.write(pgpass_config)
      end
      display "The file '#{pgpass_file}' has been created to give astroboa user permission to run postgres admin commands"
    end
  end
  
  
  def save_server_configuration
    config_file = File.expand_path(File.join('~', '.astroboa-conf.yml'))
    unless RbConfig::CONFIG['host_os'] =~ /darwin/i
      config_dir = File.join(File::SEPARATOR, 'etc', 'astroboa')
      FileUtils.mkdir_p config_dir
      config_file = File.join(config_dir, 'astroboa-conf.yml')
    end
    server_config = {}
    server_config['install_dir'] = @install_dir
    server_config['repos_dir'] = @repo_dir
    server_config['database'] = @database
    server_config['database_admin'] = @database_admin
    server_config['database_admin_password'] = @database_admin_password
    server_config['database_server'] = @database_server
    
    File.open(config_file,"w") do |f|
      f.write(YAML.dump(server_config))
    end
    display "The server configuration have been added to configuration file '#{config_file}'"
  end
  
  
  def create_central_identity_repository
    repo_name = 'identities'
    repo_config = {
      'localized_labels' => 'en:User and App Identities,el:Ταυτότητες Χρηστών και Εφαρμογών'
    }
    AstroboaCLI::Command::Repository.new([repo_name], repo_config).create
    display "Create Central 'Identities and Apps' Repository with name 'identities' : OK"
  end
  
  def set_astroboa_owner
    # In mac os x astroboa is installed and run under the ownership of the user that runs the installation command. 
    # If installation is done with sudo then we need to change the ownership of astroboa installation to the current user.
    if mac_os_x? && running_with_sudo?
      user = ENV['USER']
      FileUtils.chown_R(user, nil, @install_dir)
      display "Change (recursively) user owner of #{@install_dir} to #{user}: OK"
      
      # if repositories dir is outside the main install dir then we should change the ownership there too
      unless File.join(@install_dir, 'repositories') == @repo_dir
        FileUtils.chown_R(user, nil, @repo_dir)
        display "Change (recursively) user owner of #{@repo_dir} to #{user}: OK"
      end
      
    end
    
    # In linux a special user 'astroboa' and group 'astroboa' is created for owning a running astroboa.
    # So we need to change the ownership of the installation dir and the repositories dir to belong to user 'astroboa' and group 'astroboa'
    if linux?
      
      FileUtils.chown_R('astroboa', 'astroboa', @install_dir)
      display "Change (recursively) user and group owner of #{@install_dir} to 'astroboa': OK"
      
      # if repositories dir is outside the main install dir then we should change the ownership there too
      unless File.join(@install_dir, 'repositories') == @repo_dir
        FileUtils.chown_R('astroboa', 'astroboa', @repo_dir)
        display "Change (recursively) user and group owner of #{@repo_dir} to 'astroboa': OK"
      end
      
    end
  end
  
  def cleanup_installation
    display "Cleaning not required Installation packages..."
    FileUtils.rm File.join(@install_dir, @torquebox_package)
    display "Removed torquebox package"
    
    FileUtils.rm File.join(@install_dir, @astroboa_ear_package)
    display "Removed astroboa ear package"
    
    FileUtils.rm File.join(@install_dir, @astroboa_setup_templates_package)
    display "Removed setup templates package"
    
    FileUtils.rm File.join(@install_dir, @schemas_package)
    display "Removed schemas package"
    
    display "Installation cleanup: OK"
  end

end
  
  
  