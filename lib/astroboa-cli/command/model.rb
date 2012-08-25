# encoding: UTF-8

require 'nokogiri'
require 'fileutils'
  
# Manage your domain models
#
# Astroboa facilitates a DOMAIN DRIVEN design of applications.
# The core of your application(s) is the DOMAIN MODEL, a graph of ENTITIES that describe 
# the type of information your application(s) will create, consume and search.
#
# In order to store your application(s) data you follow three simple steps:
# 1) you create an astroboa repository (astroboa-cli repository:create)
# 2) you create your domain model by:
#   - using the Astroboa Entity Definition DSL which is very close to ActiveRecord::Schema definitions of ruby on rails
#   - directy writing an XML Schema for each entity (or a single schema to include all entity definitions)
# 3) you "associate" your domain model with the repository you just created (astroboa-cli model:associate)
#
# One of the best features of astroboa is its programming-language agnostic and dynamic domain model that can be shared between applications. 
# You do not need to create model classes for your applications. Astroboa uses the domain model that you define once and
# dynamically creates the appropriate objects for your app. 
# Additionally you can "model-as-you-go", that is you may define new entities 
# or update existing ones at any time during development or production.
# Astroboa will automatically update the APIs and the generated object instances to the updated domain model.
#
class AstroboaCLI::Command::Model < AstroboaCLI::Command::Base
  
  # model:associate REPOSITORY MODEL_DIR
  #
  # This command allows you to associate a repository with a domain model.
  # After the association is done your repository can store entities that follow the domain model.
  #
  # It is recommended to use this command only on new repositories because it does not cope with model updates 
  # (it will cause instant performace decrease because it resets the whole repository schema and most important 
  # it may render your data inaccessible if the updated model contain changes to property names or property value cardinality) 
  # If you change a domain model that has been already associated with a repository use 'astroboa-cli model:propagate_updates'   
  #
  # If you specify the 'MODEL_DIR' (i.e. where your models are stored) then your DSL model definition is expected to be 
  # in 'MODEL_DIR/dsl' and your XML Schemas to be in 'MODEL_DIR/xsd' 
  # If you do not specify the 'MODEL_DIR' then domain model is expected to be found inside current directory in 'model/dsl' and 'model/xsd'
  #
  def associate
    
    if repository = args.shift
      repository = repository.strip
    else
      error "Please specify the repository name. Usage: model:associate REPOSITORY MODEL_DIR"
    end
    
    if model_dir = args.shift
      model_dir = model_dir.strip
    else
      model_dir = File.join(Dir.getwd, 'model')
    end
    
    error <<-MSG unless Dir.exists? model_dir
    Directory #{model_dir} does not exist. 
    # If you specify the 'MODEL_DIR' then your DSL model definition is expected to be 
    # in 'MODEL_DIR/dsl' and your XML Schemas to be in 'MODEL_DIR/xsd' 
    # If you do not specify the 'MODEL_DIR' then domain model is expected to be found inside current directory in 'model/dsl' and 'model/xsd'
    MSG
    
    server_configuration = get_server_configuration
    astroboa_dir = server_configuration['install_dir']
    
    display "Looking for XML Schemas..."
    xsd_dir = File.join model_dir, 'xsd'
    model_contains_xsd = Dir.exists?(xsd_dir) && Dir.entries(xsd_dir) != [".", ".."]
    
    if model_contains_xsd
      display "Found XML Schemas in '#{xsd_dir}'"
      display "Validating XML Schemas..."
      
      tmp_dir = File.join(astroboa_dir, 'tmp')
      
      FileUtils.rm_r tmp_dir if Dir.exists? tmp_dir
      
      FileUtils.mkdir_p tmp_dir
      FileUtils.cp_r File.join(astroboa_dir, 'schemas'), tmp_dir
      
      tmp_schema_dir = File.join(tmp_dir, 'schemas')
      FileUtils.cp_r File.join(xsd_dir, '.'), tmp_schema_dir
      
      Dir[File.join(xsd_dir, '*.xsd')].each  do |schema_path|
        schema_file = schema_path.split('/').last
        
        display "Validating XML Schema: #{schema_file}"
        error "Please correct the schema file '#{schema_file}' and run the command again" unless domain_model_valid? schema_file, tmp_schema_dir
        
      end
    else
      display "No XML Schemas Found"
    end
    
    
  end
  
  # model:graph DOMAIN_MODEL
  #
  # Draws a graphic representation of the domain model
  def graph
    
  end
  
  # model:view PATH
  #
  # Displays the model of an entity or entity property
  def view
    
  end
  
  # model:list DOMAIN_MODEL
  #
  # Displays information about the domain models and their entities
  def list
    
  end
  
private

  def domain_model_valid? domain_model_file, schemas_dir
    Dir.chdir(schemas_dir) do

      # first make sure that Domain model is a well formed XML Doc and if not show errors
      domain_model_doc = Nokogiri::XML(File.read(domain_model_file))
      unless domain_model_doc.errors.empty?
        puts "#{domain_model_file} is not a well formed XML Document"
        puts domain_model_doc.errors
        return false
      else
        puts "Check if domain model is a well formed XML Document: OK"
      end
      
      # Then check if domain model is a valid XML Schema, i.e. validate it against the XML Schema schema 
      xml_schema_grammar = File.read('XMLSchema.xsd')
      xml_schema_validator = Nokogiri::XML::Schema(xml_schema_grammar)

      errors = xml_schema_validator.validate(domain_model_doc)
      if errors
        puts "Check if domain model is a valid XML Schema: Not valid XML Schema"
        errors.each do |error|
          puts error.message
        end
        return false
      else
        puts  "Check if domain model is a valid XML Schema: OK"
      end

      # Finally check if domain model is valid against its dependencies to astroboa schemas and external user-provided schemas, 
      # i.e. it properly loads and uses all its external schema dependencies
      begin
        external_schemas_validator = Nokogiri::XML::Schema(File.read(domain_model_file))
        puts 'Check if domain model is properly loading and using external schemas (i.e. astroboa model schemas + user defined schemas): OK'
        true
      catch Exception e
        puts 'Check if domain model is properly loading and using external schemas (i.e. astroboa model schemas + user defined schemas): Errors found!'
        puts external_schemas_validator.errors
        puts e.detail
        false
      end

    end

  end

end