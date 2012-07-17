# encoding: utf-8

# This file contains modifications of work covered by the following copyright and  
# permission notice:
#
# The MIT License (MIT)
# 
# Copyright © Heroku 2008 - 2012
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require "optparse"
require "astroboa-cli/util"

module AstroboaCLI
  module Command
    
    class CommandFailed  < RuntimeError; end
    
    extend AstroboaCLI::Util
    
    def self.load
      Dir[File.join(File.dirname(__FILE__), "command", "*.rb")].each do |file|
        require file
      end
      
      @@log_file = '/tmp/astroboa-cli-log.txt'
      f = File.new(@@log_file, 'w+', 0644)
      @@log = Logger.new(f)
      @@log.level = Logger::INFO
    end
    
    def self.log
      @@log
    end
    
    def self.log_file
      @@log_file
    end
    
    def self.namespaces
      @@namespaces ||= {}
    end
    
    def self.commands
      @@commands ||= {}
    end
    
    def self.current_command
      @current_command
    end

    def self.current_args
      @current_args
    end

    def self.current_options
      @current_options
    end
    
    def self.global_options
      @global_options ||= []
    end

    def self.global_option(name, *args)
      global_options << { :name => name, :args => args }
    end

    global_option :help,    "--help", "-h"
    
    def self.register_command(command)
      commands[command[:command]] = command
    end
    
    def self.register_namespace(namespace)
      namespaces[namespace[:name]] = namespace
    end
    
    def self.map_command_to_method(cmd, args=[])
      command = commands[cmd]

      unless command
        if %w( -v --version ).include?(cmd)
          display AstroboaCLI::VERSION
          exit
        end

        output_with_bang("`#{cmd}` is not an astroboa command.")

        output_with_bang("run `astroboa-cli help` to see available commands.")
        exit 1
      end

      @current_command = cmd

      opts = {}
      invalid_options = []

      parser = OptionParser.new do |parser|
        global_options.each do |global_option|
          parser.on(*global_option[:args]) do |value|
            opts[global_option[:name]] = value
          end
        end
        command[:options].each do |name, option|
          parser.on("-#{option[:short]}", "--#{option[:long]}", option[:desc]) do |value|
            opts[name.gsub("-", "_").to_sym] = value
          end
        end
      end

      begin
        parser.order!(args) do |nonopt|
          invalid_options << nonopt
        end
      rescue OptionParser::InvalidOption => ex
        invalid_options << ex.args.first
        retry
      end

      raise OptionParser::ParseError if opts[:help]

      args.concat(invalid_options)

      @current_args = args
      @current_options = opts

      [ command[:klass].new(args.dup, opts.dup), command[:method] ]
    end

    
    def self.run(command, arguments=[])
      object, method = map_command_to_method(command, arguments.dup)
      object.send(method)
    rescue => e
      error "An error has occured \n#{e.inspect}\n#{e.backtrace}"
    end
    
  end # module Command
end # module AstroboaCLI
    