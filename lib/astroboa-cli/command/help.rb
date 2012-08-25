# encoding: utf-8

require "astroboa-cli/command/base"
  
# display available commands and help
#
class AstroboaCLI::Command::Help < AstroboaCLI::Command::Base
  
  # help [COMMAND]
  #
  # list available commands or display help for a specific command
  #
  def default
    if command = args.shift
      help_for_command(command)
    else
      help_for_root
    end
  end
  
private
  
  def subcommands_in_namespace(name)
    AstroboaCLI::Command.commands.values.select do |command|
      command[:namespace] == name && command[:command] != name
    end
  end
    
  def help_for_root
    puts "Usage: astroboa-cli COMMAND [command-specific-options]"
    puts
    puts "To get help about a top command, type \"astroboa-cli help command\""
    puts "Available top commands:"
    summary_for_namespaces
    puts
  end
  
  def summary_for_namespaces
    size = longest(AstroboaCLI::Command.namespaces.values.map { |namespace| namespace[:name] })
    AstroboaCLI::Command.namespaces.values.sort_by {|namespace| namespace[:name]}.each do |namespace|
      name = namespace[:name]
      puts "  %-#{size}s  # %s" % [ name, namespace[:description] ]
    end
  end
  
  def help_for_subcommands_in_namespace(namespace)
    subcommands = subcommands_in_namespace(namespace)

    unless subcommands.empty?
      size = longest(subcommands.map { |c| c[:banner] })
      subcommands.sort_by { |c| c[:banner].to_s }.each do |command|
        next if command[:help] =~ /DEPRECATED/
        puts "  %-#{size}s  # %s" % [ command[:banner], command[:summary] ]
      end
    end
  end
  
  def help_for_command(name)
    puts AstroboaCLI::Command.namespaces[name][:long_description] if AstroboaCLI::Command.namespaces[name]
    puts
    command = AstroboaCLI::Command.commands[name]
    
    if command
      puts "Usage: astroboa-cli #{command[:banner]}"

      if command[:help].strip.length > 0
        command[:help].split("\n")[1..-1].each do |line|
          if line =~ /#/
            option_parts = line.split('#')
            puts "#{option_parts[0]}"
            option_parts[1..-1].each do |sentence|
              puts "\t #{sentence}"
            end
            puts
          elsif
            puts line
          end
        end
        
        puts
      end
    end
    
    # if there are sub commands inform the user
    if subcommands_in_namespace(name).size > 0
      puts "This top command supports the following sub-commands, type \"astroboa-cli help SUB-COMMAND\" to get help:"
      puts
      help_for_subcommands_in_namespace(name)
      puts
    elsif command.nil? # if there are not subcommands and the top command itself does not exist display an error
      error "#{name} is not an astroboa command. See 'astroboa-cli help'."
    end
  end
  
end