# encoding: utf-8

require 'yaml'
require 'zip/zip'
require 'nokogiri'
require 'colorize'

module AstroboaCLI
  module Util
    
    # This code is from Sprinkle that in turn got it from Chef !!
    class TemplateError < RuntimeError
      attr_reader :original_exception, :context
      SOURCE_CONTEXT_WINDOW = 2 unless defined? SOURCE_CONTEXT_WINDOW

      def initialize(original_exception, template, context)
        @original_exception, @template, @context = original_exception, template, context
      end

      def message
        @original_exception.message
      end

      def line_number
        @line_number ||= $1.to_i if original_exception.backtrace.find {|line| line =~ /\(erubis\):(\d+)/ }
      end

      def source_location
        "on line ##{line_number}"
      end

      def source_listing
        return nil if line_number.nil?

        @source_listing ||= begin
          line_index = line_number - 1
          beginning_line = line_index <= SOURCE_CONTEXT_WINDOW ? 0 : line_index - SOURCE_CONTEXT_WINDOW
          source_size = SOURCE_CONTEXT_WINDOW * 2 + 1
          lines = @template.split(/\n/)
          contextual_lines = lines[beginning_line, source_size]
          output = []
          contextual_lines.each_with_index do |line, index|
            line_number = (index+beginning_line+1).to_s.rjust(3)
            output << "#{line_number}: #{line}"
          end
          output.join("\n")
        end
      end

      def to_s
        "\n\n#{self.class} (#{message}) #{source_location}:\n\n" +
          "#{source_listing}\n\n  #{original_exception.backtrace.join("\n  ")}\n\n"
      end
    end
  
    
    def display(msg="", new_line=true, add_to_log=true)
      if new_line
        puts(msg)
      else
        print(msg)
        STDOUT.flush
      end
      log.info msg if add_to_log
    end
    
    
    def error(msg, add_to_log=true)
      STDERR.puts(format_with_bang(msg))
      log.error msg if add_to_log   
      exit 1
    end
    
    
    def fail(message)
      raise AstroboaCLI::Command::CommandFailed, message
    end
    
    
    def format_with_bang(message)
      return '' if message.to_s.strip == ""
      " !    " + message.split("\n").join("\n !    ")
    end
    
    
    def output_with_bang(message="", new_line=true)
      return if message.to_s.strip == ""
      display(format_with_bang(message), new_line)
    end
    
    
    def ask
      STDIN.gets.strip
    end


    def shell(cmd)
      FileUtils.cd(Dir.pwd) {|d| return `#{cmd}`}
    end


    def longest(items)
      items.map { |i| i.to_s.length }.sort.last
    end
    
    
    def has_executable(path)
      # If the path includes a forward slash, we're checking
      # an absolute path. Otherwise, we're checking a global executable
      if path.include?('/')
        commands = "test -x #{path}"
      else
        command = "[ -n \"`echo \\`which #{path}\\``\" ]"
      end
      process_os_command command
    end


    # Same as has_executable but with checking for e certain version number.
    # If version number contains dots it, they should be escaped, e.g. "1\\.6"
    # Last option is the parameter to append for getting the version (which
    # defaults to "-v").
    def has_executable_with_version(path, version, get_version = '-v')
      if path.include?('/')
        command = "[ -x #{path} -a -n \"`#{path} #{get_version} 2>&1 | egrep -e \\\"#{version}\\\"`\" ]"
      else
        command = "[ -n \"`echo \\`which #{path}\\``\" -a -n \"`\\`which #{path}\\` #{get_version} 2>&1 | egrep -e \\\"#{version}\\\"`\" ]"
      end
      process_os_command command
    end


    # Same as has_executable but checking output of a certain command
    # with grep.
    def has_version_in_grep(cmd, version)
       process_os_command "[ -n \"`#{cmd} 2> /dev/null | egrep -e \\\"#{version}\\\"`\" ]"
    end
    
    
    def process_os_command(command)
      system command
      return false if $?.to_i != 0
      return true
    end
    
    
    def extract_archive_command(archive_name)
      case archive_name
      when /(tar.gz)|(tgz)$/
        'tar xzf'
      when /(tar.bz2)|(tb2)$/
        'tar xjf'
      when /tar$/
        'tar xf'
      when /zip$/
        'unzip -o -q'
      else
        fail "Unknown binary archive format: #{archive_name}"
      end
    end
    
    
    def unzip_file (file, destination)
      Zip::ZipFile.open(file) { |zip_file|
       zip_file.each { |f|
         next unless f.file?
         f_path=File.join(destination, f.name)
         FileUtils.mkdir_p(File.dirname(f_path))
         zip_file.extract(f, f_path) unless File.exist?(f_path)
       }
      }
    end
    
    
    def render_template_to_file(template_path, context, file_path)
      require 'erubis'

      begin
        template = File.read template_path
        eruby = Erubis::Eruby.new(template)
        File.open file_path, "w" do |f|
          f << eruby.evaluate(context)
        end
      rescue Object => e
        raise TemplateError.new(e, template, context)
      end

    end
    
    
    # Delete file lines between two regular expressions, /foo/ and /bar/, including the lines
    # that match the regular expressions, e.g. delete file lines between two comments, including the comments
    # from_regex and to_regex should be specified without leading and trailing slashes i.e. "string_to_match" and not "/string_to_match/"
    def delete_file_content_between_regex(filename, from_regex, to_regex)
      from_regex_obj = %r{#{from_regex}}
      to_regex_obj = %r{#{to_regex}}
      found_boundary = false
      file_lines = File.readlines(filename)
      File.open(filename, "w") do |f|
        file_lines.each do |line|
          found_boundary = true if line =~ from_regex_obj
          f.puts line unless found_boundary
          found_boundary = false if line =~ to_regex_obj
        end
      end
    end
    
    
    def delete_file_lines(filename, lines_to_delete)
      file_lines = File.readlines(filename)
      lines_to_delete.each do |index|
        file_lines.delete_at(index)
      end 
      File.open(filename, "w") do |f| 
        f.write lines_to_delete.join
      end
    end
    
    
    def windows?
      RbConfig::CONFIG['host_os'] =~ /mswin/i
    end


    def mac_os_x?
      RbConfig::CONFIG['host_os'] =~ /darwin/i
    end
    
    
    def linux?
      RbConfig::CONFIG['host_os'] =~ /linux/i
    end
    
    
    def running_with_sudo?
      Process.uid == 0
    end
    
    
    def check_if_running_with_sudo
      display "You need sudo privileges to run this command. Checking..."
      error <<-MSG.gsub(/^ {6}/, '') unless running_with_sudo?
      You are not running with sudo privileges. Please run astroboa-cli with sudo
      If you installed ruby with 'rbenv' you need to install 'rbenv-sudo' plugin and then run 'rbenv sudo astroboa-cli <COMMAND>'
      For 'rbenv-sudo' installation check ruby installation instructions at https://github.com/betaconcept/astroboa-cli
      If you manage your rubies with 'rvm' the you should use the 'rvmsudo' command: 'rvmsudo astroboa-cli <COMMAND>'
      MSG
  
      display "Running with sudo privileges: OK"
    end
    
    
    def dir_writable?(dir)
      until FileTest.directory?(dir)
        dir = File.dirname(dir)
      end
      File.writable? dir
    end
    
    
    def gem_available?(name)
       Gem::Specification.find_by_name(name)
    rescue Gem::LoadError
       false
    rescue
       Gem.available?(name)
    end
    
    
    def astroboa_running?
      server_config = get_server_configuration
      jboss_dir = File.join(server_config['install_dir'], 'torquebox', 'jboss')
      system %(ps -ef | grep "org.jboss.as.standalone -Djboss.home.dir=#{jboss_dir}" | grep -vq grep)
    end
    
        
    def get_server_conf_file
      return File.expand_path(File.join("~", ".astroboa-conf.yml")) if mac_os_x?
      return File.join(File::SEPARATOR, 'etc', 'astroboa', 'astroboa-conf.yml')
    end


    def save_server_configuration(server_configuration)
      File.open(get_server_conf_file, "w") do |f|
        f.write(YAML.dump(server_configuration))
      end
    end


    def get_server_configuration
      server_conf_file = get_server_conf_file
      return YAML.load(File.read(server_conf_file)) if File.exists? server_conf_file
      error "Server configuration file: '#{server_conf_file}' does not exist"
    end
    
    
    def repository_in_server_config?(server_config, repo_name)
      return server_config.has_key?('repositories') && server_config['repositories'].has_key?(repo_name)
    end
    
    
    def repository_in_repos_config?(repos_dir, repository_name)
      astroboa_repos_config = File.join(repos_dir, "repositories-conf.xml")

      repo_conf = nil

      if File.exists? astroboa_repos_config
        File.open(astroboa_repos_config, 'r') do |f|
          repo_conf = Nokogiri::XML(f) do |config|
            config.noblanks
          end
        end
        
        repo_nodes = repo_conf.xpath(%(//repository[@id="#{repository_name}"]))
        return true if !repo_nodes.empty?
      end

      return false
    end
    
    
    # check that repo is consistently configured, 
    # i.e Its directory exists AND it is specified in server configuration AND its repo config file exists
    def repository?(server_configuration, repository_name)
      repos_dir = server_configuration['repos_dir']
      astroboa_dir = server_configuration['install_dir']
      repo_dir = File.join(repos_dir, repository_name)
      
      return true if File.exists?(repo_dir) && repository_in_repos_config?(repos_dir, repository_name) && repository_in_server_config?(server_configuration, repository_name)
      
      return false;
    end
    
    
    def runs_with_jruby?
      (defined? RUBY_ENGINE && RUBY_ENGINE == 'jruby') || RUBY_PLATFORM == "java"
    end
    
    
    def jruby_version_ok?
      return false unless defined? JRUBY_VERSION

      jruby_version_numbers = JRUBY_VERSION.split(".")

      return false unless jruby_version_numbers[0].to_i == 1 && 
        ((jruby_version_numbers[1].to_i == 6 && jruby_version_numbers[2].to_i >= 7) || jruby_version_numbers[1].to_i == 7)
      return true
    end
    
    
    def ruby_version_ok?
      return false unless defined? RUBY_VERSION

      ruby_version_numbers = RUBY_VERSION.split(".")

      return false unless (ruby_version_numbers[0].to_i == 1 && ruby_version_numbers[1].to_i >= 9) || ruby_version_numbers[0].to_i == 2
      return true
    end
    
    
    def ruby_ok?
      ruby_installation_instructions_message =<<-RUBY_INSTALL_MESSAGE
      You can easily install ruby with 'rbenv' or 'rvm' utility programs.

      ----------------------------------
      We recommend to install ruby using the 'rbenv' and 'ruby-build' utility commands.
      On Mac OS X  to install 'rbenv' and 'ruby-build' using the Homebrew (http://mxcl.github.com/homebrew/) package manager do:
        $ brew update
        $ brew install rbenv
        $ brew install ruby-build

      To install ruby version 2.1.1 do:
        $ rbenv install 2.1.1

      To set the global version of Ruby to be used in all your shells do:
        $ rbenv global 2.1.1

      To set ruby 2.1.1 as a local per-project ruby version by writing the version name to an .rbenv-version file in the current directory do:

        $ rbenv local 2.1.1

      To set ruby 2.1.1 as the version to be used only in the current shell (sets the RBENV_VERSION environment variable in your shell) do:

        $ rbenv shell 2.1.1

      ------------------------------- 
      If you prefer to use 'rvm' as your ruby management utility use the following command to install it for a single user:

      user$ curl -L get.rvm.io | bash -s stable 

      For multi-user installation and detailed rvm installation instructions check: https://rvm.io/rvm/install/    

      After 'rvm' has been installed run the following commands to install ruby 2.1.1:
      rvm install 2.1.1
      rvm use 2.1.1
      RUBY_INSTALL_MESSAGE

      ruby_wrong_version_message =<<-RUBY_VERSION_MESSAGE
      It seems that you are not running ruby 1.9.x. or later
      Your current Ruby Version is: #{RUBY_VERSION} 
      Astroboa CLI requires your ruby version to be 1.9.x or later (e.g. 1.9.2 or 1.9.3 or 2.1.1).

      #{ruby_installation_instructions_message}
      RUBY_VERSION_MESSAGE

      error ruby_wrong_version_message unless ruby_version_ok?
      #display "Checking if your ruby version is 1.9.x: OK"
    end
    
    
    def jruby_ok?
      install_jruby_with_rvm_message =<<-RVM_INSTALL_MESSAGE
      We recommend to install jruby using the "RVM" utility command
      To install "rvm" for a single user (i.e. the user that will run astroboa-cli) login as the user and run the following command:

      user$ curl -L get.rvm.io | bash -s stable 

      For multi-user installation and detailed rvm installation instructions check: https://rvm.io/rvm/install/    

      After RVM has been installed run the following commands to install jruby:
      rvm install jruby-1.6.7
      rvm use jruby-1.6.7
      RVM_INSTALL_MESSAGE

      jruby_not_running_message =<<-JRUBY_MESSAGE
      It seems that you are not running jruby.
      Astroboa requires jruby version 1.6.7 or above. 
      Please install jruby version 1.6.7 or above and run the astroboa-cli command again

      #{install_jruby_with_rvm_message}
      JRUBY_MESSAGE

      jruby_wrong_version_message =<<-JRUBY_VERSION_MESSAGE
      It seems that you are not running the required jruby version
      Your jruby version is: #{JRUBY_VERSION}
      Astroboa requires jruby version 1.6.7 or above. 
      Please install jruby version 1.6.7 or above and run the astroboa-cli command again

      #{install_jruby_with_rvm_message}
      JRUBY_VERSION_MESSAGE

      ruby_wrong_version_message =<<-RUBY_VERSION_MESSAGE
      It seems that you are not running jruby in 1.9 mode.
      Your current Ruby Version is: #{RUBY_VERSION} 
      Astroboa requires your jruby to run in 1.9 mode. 
      To make jruby run in 1.9 mode add the following to your .bash_profile
      export JRUBY_OPTS=--1.9 

      You need to logout and login or run "source ~/.bash_profile" in order to activate this setting
      RUBY_VERSION_MESSAGE

      error jruby_not_running_message unless runs_with_jruby?
      error jruby_wrong_version_message unless jruby_version_ok?
      error ruby_wrong_version_message unless ruby_version_ok?
      display "Checking if you are running jruby version 1.6.7 or above in 1.9 mode: OK"
    end
    
    
    def get_postgresql_config(server_configuration)
      database_admin = server_configuration['database_admin']
      database_admin_password = server_configuration['database_admin_password']
      database_server = server_configuration['database_server']
      return database_admin, database_admin_password, database_server
    end
    
    
    def load_pg_library
      # try to load the 'pg' library if repository is backed by postgres 
      error <<-MSG unless gem_available?('pg')
      You should manually install the 'pg' gem if you want to create repositories backed by postgres
      astroboa-cli gem does not automatically install 'pg' gem since in some environments (e.g. MAC OS X) this might require 
      to have a local postgres already installed, which in turn is too much if you do not care about postgres.
    	In *Ubuntu Linux* run first 'sudo apt-get install libpq-dev' and then run 'gem install pg'.
    	For MAC OS x read http://deveiate.org/code/pg/README-OS_X_rdoc.html to learn how to install the 'pg' gem.
      MSG

      require 'pg'  
    end
    
    
    def postgres_connectivity?(database_server, database_user, database_user_password)
      load_pg_library
      
      begin
        conn = PG.connect(
          host:     database_server, 
          port:     '5432', 
          dbname:   'postgres', 
          user:     database_user, 
          password: database_user_password)
          conn != nil ? true : false
      rescue PG::Error => e
        display %(An error has occured while trying to establish a connection to postgres database)
        display %(The error is: "#{e.message}")
        false
      ensure
        conn.finish if conn && !conn.finished?
      end
    end
    
    
    def create_postgresql_db(server_configuration, database_name)
      load_pg_library
      
      database_admin, database_admin_password, database_server = get_postgresql_config(server_configuration)
      
      begin
        conn = PG.connect(
          host:     database_server, 
          port:     '5432', 
          dbname:   'postgres', 
          user:     database_admin, 
          password: database_admin_password)

        # check if db exists
        res = conn.exec("SELECT COUNT(*) FROM pg_database WHERE datname=$1",[database_name])
        unless res.entries[0]['count'].to_i == 0
          display "Database #{database_name} exists. You may run the command with --db_name repo_db_name to specify a different database name" 
          raise
        end
        
        display "Check that database #{database_name} does not exist: OK"
        
        res = conn.exec("CREATE DATABASE #{database_name} ENCODING 'UNICODE'")
        if res.result_status == PG::Result::PGRES_COMMAND_OK
          display %(Create Postges database "#{database_name}" : OK)
        else
          display "Failed to create postgres database #{database_name}. The error is #{res.error_message}"
          raise 
        end
      rescue PG::Error => e
        display %(An error has occured during the creation of postgres database "#{database_name}")
        display %(The error is: "#{e.message}")
        display %(The error trace is \n #{e.backtrace.join("\n")})
        raise
      ensure
        conn.finish if conn && !conn.finished?
      end
    end


    def drop_postgresql_db(server_configuration, database_name)
      load_pg_library
      
      database_admin, database_admin_password, database_server = get_postgresql_config(server_configuration)
      
      begin
        conn = PG.connect(
          :host     => database_server, 
          :port     => '5432', 
          :dbname   => 'postgres', 
          :user     => database_admin, 
          :password => database_admin_password)

        # check if db exists
        res = conn.exec("SELECT COUNT(*) FROM pg_database WHERE datname=$1",[database_name])
        if res.entries[0]['count'] == 0 
          display "Cannot remove database #{database_name} because it does not exist"
          raise
        end

        res = conn.exec("DROP DATABASE #{database_name}")
        if res.result_status == PG::Result::PGRES_COMMAND_OK
          display %(Delete Postges database "#{database_name}" : OK)
        else
          display "Failed to delete postgres database #{database_name}. The error is #{res.error_message}"
          raise 
        end

      rescue PG::Error => e
        display %(An error has occured during the deletion of postgres database "#{database_name}")
        display %(The error is: "#{e.message}")
        display %(The error trace is \n #{e.backtrace.join("\n")})
        raise
      ensure
        conn.finish if conn && !conn.finished?
      end
    end


    # remove leading and trailing white space from XML Document text nodes
    # xml_doc should be a Nokogiri::XML:Document or Nokogiri::XML::Node
    def strip_text_nodes xml_doc
      xml_doc.traverse do |node|
        if node.text?
          node.content = node.content.strip
        end
      end
    end
    
    # write XML document to a file
    # document should be a Nokogiri::XML:Document or Nokogiri::XML::Node
    def write_xml document, file_full_path
      strip_text_nodes document

      File.open(file_full_path, 'w') do |f|
        document.write_xml_to(f, :indent => 1, :indent_text => "\t", :encoding => 'UTF-8')
      end
    end
    
    
    def get_password(msg)
      password = ""
      print msg.blue.underline
      begin
        system "stty -echo 2>/dev/null"
        password = STDIN.gets.chomp
        system "stty echo 2>/dev/null"
        puts
        password
      rescue => e
        system "stty echo"
        error "An error occurred. The error is: #{e.message}"
      end
    end
    
  end
end