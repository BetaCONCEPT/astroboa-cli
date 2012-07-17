# encoding: utf-8

require "astroboa-cli/command/base"
require "astroboa-cli/version"

module AstroboaCLI::Command
  
  # display version
  #
  class Version < Base
    
    # version
    #
    # show astroboa client version
    #
    def default
      display AstroboaCLI::VERSION
    end
  end # class Version 
  
end # module AstroboaCLI::Command