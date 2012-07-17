# encoding: utf-8

require "astroboa-cli/command"

module AstroboaCLI
  
  class CLI
    def self.start(*args)
        command = args.shift.strip rescue "help"
        AstroboaCLI::Command.load
        AstroboaCLI::Command.run(command, args)
      end
    
  end
  
end