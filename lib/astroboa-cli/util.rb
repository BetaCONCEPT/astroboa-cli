# encoding: utf-8

require 'yaml'
require 'zip/zip'

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
    
    
    def repository?(server_config, repo_name)
      return server_config.has_key?('repositories') && server_config['repositories'].has_key?(repo_name)
    end

  end
end