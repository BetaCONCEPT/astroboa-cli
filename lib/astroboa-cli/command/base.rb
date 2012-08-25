# encoding: UTF-8

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


require 'logger'

module AstroboaCLI::Command
  
  class Base
    include AstroboaCLI::Util
    
    def self.namespace
      self.to_s.split("::").last.downcase
    end
    
    attr_reader :args
    attr_reader :options
    attr_reader :log
    attr_reader :log_file

    def initialize(args=[], options={})
      @args = args
      @options = options
      
      @log_file = '/tmp/astroboa-cli-log.txt'
      @log = Logger.new(@log_file)
      @log.level = Logger::INFO
      
      # Check if the proper version of ruby is running
      ruby_ok?
    end
    
  protected
    def self.inherited(klass)
      return if klass == AstroboaCLI::Command::Base
      
      help = extract_help_from_caller(caller.first)

      AstroboaCLI::Command.register_namespace(
        :name => klass.namespace,
        :description => help.split("\n").first,
        :long_description => help.split("\n")
      )
    end
  
    def self.method_added(method)
      return if self == AstroboaCLI::Command::Base
      return if private_method_defined?(method)
      return if protected_method_defined?(method)

      help = extract_help_from_caller(caller.first)
      
      resolved_method = (method.to_s == "default") ? nil : method.to_s
      command = [ self.namespace, resolved_method ].compact.join(":")
      banner = extract_banner(help) || command
      permute = !banner.index("*")
      banner.gsub!("*", "")

      AstroboaCLI::Command.register_command(
        :klass       => self,
        :method      => method,
        :namespace   => self.namespace,
        :command     => command,
        :banner      => banner,
        :help        => help,
        :summary     => extract_summary(help),
        :description => extract_description(help),
        :options     => extract_options(help),
        :permute     => permute
      )
    end
    
    # Parse the caller format and identify the file and line number as identified
    # in : http://www.ruby-doc.org/core/classes/Kernel.html#M001397.  This will
    # look for a colon followed by a digit as the delimiter.  The biggest
    # complication is windows paths, which have a color after the drive letter.
    # This regex will match paths as anything from the beginning to a colon
    # directly followed by a number (the line number).
    #
    # Examples of the caller format :
    # * c:/Ruby192/lib/.../lib/astroboa-cli/command/server.rb:8:in `<module:Command>'
    #
    def self.extract_help_from_caller(line)
      # pull out of the caller the information for the file path and line number
      if line =~ /^(.+?):(\d+)/
        return extract_help($1, $2)
      end
      raise "unable to extract help from caller: #{line}"
    end

    def self.extract_help(file, line)
      buffer = []
      lines  = File.read(file).split("\n")

      catch(:done) do
        (line.to_i-2).downto(0) do |i|
          case lines[i].strip[0..0]
            when "", "#" then buffer << lines[i]
            else throw(:done)
          end
        end
      end

      buffer.map! do |line|
        line.strip.gsub(/^#/, "")
      end

      buffer.reverse.join("\n").strip
    end

    def self.extract_banner(help)
      help.split("\n").first
    end

    def self.extract_summary(help)
      extract_description(help).split("\n").first
    end

    def self.extract_description(help)
      lines = help.split("\n").map { |l| l.strip }
      lines.shift
      lines.reject do |line|
        line =~ /^-(.+)#(.+)/
      end.join("\n").strip
    end

    def self.extract_options(help)
      help.split("\n").map { |l| l.strip }.select do |line|
        line =~ /^-(.+)#(.+)/
      end.inject({}) do |hash, line|
        description = line.split("#", 2).last.strip
        long  = line.match(/--([A-Za-z_\- ]+)/)[1].strip
        short = line.match(/-([A-Za-z ])/)[1].strip
        hash.update(long.split(" ").first => { :desc => description, :short => short, :long => long })
      end
    end

    def extract_option(name, default=true)
      key = name.gsub("--", "").to_sym
      return unless options[key]
      value = options[key] || default
      block_given? ? yield(value) : value
    end

  
  end # class base
    
end # Module AstroboaCLI::Command