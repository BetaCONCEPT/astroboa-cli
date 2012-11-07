# encoding: utf-8

require 'astroboa-cli/command/base'
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
  
  # model:associate REPOSITORY [MODELS_DIR]
  #
  # This command allows you to associate a repository with a domain model.
  # After the association is done your repository can store entities that follow the domain model.
  #
  # It is recommended to use this command either to bootstrap new repositories with a domain model 
  # or use it with CAUTION to update the domain model of an existing repository.
  # It is SAFE to use it for domain model updates ONLY WHEN YOU ADD new object types or add new properties to existing types. 
  # This command does not cope with model updates that change existing object type names or change existing property names, 
  # property types and property value cardinality. I you do such updates and use this command, it may render your data inaccessible. 
  # In any case it will not delete any existing data so you can instantly recover your data visibility if you put back your old model.
  #
  # The command can be used both when the server is stoppped as well as when the server is up. 
  # So you can do LIVE UPDATES to your schema but be warned that a schema change 
  # will cause a few seconds performace decrease on a live system.
  # 
  # If in some case you need to change existing object type names or change existing property names, property types 
  # and property value cardinality in your domain model then use 'astroboa-cli model:propagate_updates' 
  # in order to propagate the changes to a repository. This might require to alter data 
  # in the repository as opposed to 'model:associate' that never touches the stored data and 
  # so it should be used ONLY if you ADD new features to your model.
  #
  # If you specify the 'MODELS_DIR' (i.e. where your models are stored) then your DSL model definition is expected to be 
  # in 'MODELS_DIR/dsl' and your XML Schemas to be in 'MODELS_DIR/xsd' 
  # If you do not specify the 'MODELS_DIR' then the domain model is expected to be found inside the current directory in 'models/dsl' and 'models/xsd'
  #
  def associate
    
    if repository = args.shift
      repository = repository.strip
    else
      error "Please specify the repository name. Usage: model:associate REPOSITORY MODEL_DIR"
    end
    
    server_configuration = get_server_configuration
    
    error "Repository '#{repository}' does not exist or it is not properly configured (use astroboa-cli repository:list to see available repositories)" unless repository?(server_configuration, repository)
    
    if models_dir = args.shift
      models_dir = models_dir.strip
    else
      models_dir = File.join(Dir.getwd, 'models')
    end
    
    error <<-MSG unless Dir.exists? models_dir
    Directory #{models_dir} does not exist. 
    If you specify the 'MODELS_DIR' then your DSL model definition is expected to be 
    in 'MODELS_DIR/dsl' and your XML Schemas to be in 'MODELS_DIR/xsd' 
    If you do not specify the 'MODELS_DIR' then domain model is expected to be found inside current directory in 'models/dsl' and 'models/xsd'
    MSG
    
    astroboa_dir = server_configuration['install_dir']
    
    display "Looking for XML Schemas..."
    xsd_dir = File.join models_dir, 'xsd'
    models_contain_xsds = Dir.exists?(xsd_dir) && Dir.entries(xsd_dir) != [".", ".."]
    
    if models_contain_xsds
      display "Found XML Schemas in '#{xsd_dir}'"
      display "Validating XML Schemas..."
      
      tmp_dir = File.join(astroboa_dir, 'tmp')
      
      FileUtils.rm_r tmp_dir if Dir.exists? tmp_dir
      
      FileUtils.mkdir_p tmp_dir
      FileUtils.cp_r File.join(astroboa_dir, 'schemas'), tmp_dir
      
      tmp_schema_dir = File.join(tmp_dir, 'schemas')
      FileUtils.cp_r Dir.glob(File.join(xsd_dir, '*.xsd')), tmp_schema_dir
      
      # Validate schemas in domain model
      Dir[File.join(xsd_dir, '*.xsd')].each  do |schema_path|
        schema_file = schema_path.split('/').last
        
        display
        display '-------------------------------------------------'
        display "Validating XML Schema: #{schema_file}"
        error "Please correct the schema file '#{schema_file}' and run the command again" unless domain_model_valid? schema_file, tmp_schema_dir
      end
      
      # copy schemas to repository schemas directory
      repository_schema_dir = File.join(server_configuration['repos_dir'], repository, 'astroboa_schemata')
      FileUtils.cp_r Dir.glob(File.join(xsd_dir, '*.xsd')), repository_schema_dir
      
      display
      display '-------------------------------------------------'
      display '-------------------------------------------------'
      display "Repository '#{repository}' associated to XML Schemas in '#{xsd_dir}': OK"
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
  
  # model:create_object_type NAME
  #
  # Creates a new object type. The name of the new object type (the class name in programming terms) will be NAME
  #
  # It will create a new XML Schema and will add the required definitions (namespaces, imports, xml tags) for the new object type.
  # The generated file will be named '{NAME}.xsd'
  # If you do not specify a namespace for your new object type (using --namespace) then the namespace 'http://astroboa/schema/{NAME}' will be used by default
  #
  # If you specify the 'MODELS_DIR' (i.e. where your models are stored) then the XML Schema file will be written inside '{MODELS_DIR}/xsd/' ('{MODELS_DIR}/xsd' will be created if it does not exist)
  # If you do not specify the 'MODELS_DIR' then the XML Schema file will be written in 'models/xsd/' inside the current directory ('./models/xsd' will be created if it does not exist). 
  #
  # The created object type will not have any properties. Use the 'model:add_property' command to add properties to your new type.
  #
  # NOTE: If you are creating XML Schema files manually besides using this command please follow the same convension 
  # that this command follows, that is to keep each object type in a separate file and name your file after the name of the type.
  #
  # -d, --models_dir MODELS_DIR                 # The directory (absolute path) where your models are stored. # The generated XML Schema file will be written inside '{MODELS_DIR}/xsd/' # If directory {MODELS_DIR}/xsd does not exist, it will be created.
  # -n, --namespace NAMESPACE                   # The namespace to be used for your new object type # (i.e. the corresponding entity tag will be namespaced with the provided namespace) # If not specified, the default namespace 'http://astroboa/schema/{NAME}' will be used (NAME is the name of your object type).
  # -l, --localized_labels OBJECT_TYPE_LABELS   # Provide friendly object type names for different languages # By default the 'NAME' of the object type will be used as the english label # Example: -l en:Movie,fr:Film,es:Filme
  #
  def create_object_type
    if object_type = args.shift
      object_type = object_type.strip
    else
      error "Please specify a name for your new object type. Usage: model:create_object_type NAME"
    end
     
    namespace = options[:namespace] ||= "http://astroboa/schema/#{object_type}"
    models_dir = options[:models_dir] ||= File.join(Dir.getwd, 'models')
    localized_labels = options[:localized_labels] ||= "en:#{object_type}"
    localized_labels_map = {}
    localized_labels.split(',').each {|loc_lab| loc_lab_array = loc_lab.split(':'); localized_labels_map[loc_lab_array[0]] = loc_lab_array[1]}
    
    xsd_dir = File.join models_dir, 'xsd'
    
    unless Dir.exists? xsd_dir
      FileUtils.mkdir_p xsd_dir
    end 
    
    schema_file = File.join xsd_dir, "#{object_type}.xsd"
    
    error <<-MSG if File.exists? schema_file
    XML Schema file '#{schema_file}' exists.
    This means that you have already defined a type named '#{object_type}' (the command creates each object type 
    in a different schema file named after the object type name).
    There is also the possibility that you have manually created the file '#{schema_file}'. 
    If you are creating XML Schema files manually please follow the convension 
    to keep each object type in a separate file and name your file after the name of the type.
    MSG
    
    # TODO: Extra check all other schemas to verify that user has not manually add this type
    
    server_configuration = get_server_configuration
    astroboa_dir = server_configuration['install_dir']
    
    object_type_template = File.join(astroboa_dir, 'astroboa-setup-templates', 'object_type_template.xsd')
    context = {namespace: namespace, object_type: object_type, localized_labels_map: localized_labels_map}
    render_template_to_file(object_type_template, context, schema_file)
    
    display "Generate schema file '#{schema_file}' for new object type '#{object_type}': OK"
    display "You can now use 'model:add_property' to add properties to your new object type."
    display "When you finish adding properties to your type use 'model:associate' to associate a repository with your new object type and start creating object instances of this type" 
  end
  
  
  # model:add_property PROPERTY_NAME OBJECT_TYPE
  #
  # Adds a new property with name 'PROPERTY_NAME' to 'OBJECT_TYPE'. If '--update' is specified it updates an existing property
  #
  # If you specify the 'MODELS_DIR' (i.e. where your models are stored) then the XML Schema that contains the object type definition 
  # is expected to be found in '{MODELS_DIR}/xsd/{OBJECT_TYPE}.xsd' 
  # If you do not specify the 'MODELS_DIR' then the XML Schema that contains the object type definition is expected to be found inside the current directory in 'models/xsd/{OBJECT_TYPE}.xsd'
  #
  # -d, --models_dir MODELS_DIR                 # The directory (absolute path) where your models are stored. # Default is './models' # The XML Schema file that contains the object type definition is expected to be found in '{MODELS_DIR}/xsd/{OBJECT_TYPE}.xsd'
  # -t, --type TYPE                             # The property type. # Accepted types are: string,integer,double,boolean,date,dateTime,binary,topic_ref,object_ref,complex,[USER_DEFINED_TYPE]. Default type is 'string'.
  # -x, --max_values MAX_NUM_OF_VALUES          # The maximum number of values that are permitted for this property. # Specify '1' if you want to store only one value. # Specify 'unbounded' if you want to store a list of values without an upper limit in list size. # Default is '1'.
  # -n, --min_values MIN_NUM_VALUES             # The minimum number of values that are permitted for this property. # Specify '0' to designate a non mandatory field. # Specify '1' to designate a mandatory field. # Default is '0'.
  # -p, --parent PROPERTY_NAME                  # The name of an EXISTING property that will contain this property. # The parent property should always be of type 'complex'. # Properties of type 'complex' act as a grouping container for their child properties. # Imagine them as named fieldsets of a form # E.g. The 'complex' property 'address' is the parent (container) of the properties 'street', 'city', 'zipcode', 'country'. # You may arbitrarily nest 'complex' properties inside other 'complex' properties to create property trees. 
  # -l, --localized_labels PROPERTY_NAME_LABELS # Provide friendly names for the property in different languages # By default the 'PROPERTY_NAME' will be used as the english label # Example: -l en:First Name,fr:Prénom,es:Primer Nombre
  # -u, --update                                # Use this option to specify whether you want to update an EXISTING property. # If the property with 'PROPERTY_NAME' exists and you do not use this option then NO UPDATE will be performed. # The default values for property attributes are not used during a property update. # ONLY the property attributes that are expicitly specified with the options will be updated. # E.g. if you give 'astroboa-cli model:add_property age person -t integer --update' # and the property 'age' exists then only its 'type' will be changed. # The 'minValues', 'maxValues', 'localized_labels' will keep their existing values. 
  #
  def add_property
    if property_name = args.shift
      property_name = property_name.strip
    else
      error "Please specify a name for the property. Usage: model:add_property PROPERTY_NAME OBJECT_TYPE"
    end
    
    if object_type = args.shift
      object_type = object_type.strip
    else
      error "Please specify the object type for which you want to add / update a property. Usage: model:add_property PROPERTY_NAME OBJECT_TYPE"
    end
    
    models_dir = options[:models_dir] ||= File.join(Dir.getwd, 'models')
    xsd_dir = File.join models_dir, 'xsd'
    schema_file = File.join xsd_dir, "#{object_type}.xsd"
    
    error <<-MSG unless File.exists? schema_file
    XML Schema file #{schema_file} does not exist.
    The XML Schema that contains the object type definition 
    is expected to be found in 'MODELS_DIR/xsd/OBJECT_TYPE.xsd'
    If you do not specify the MODELS_DIR with '--models_dir MODELS_DIR' 
    the default is './models'
    MSG
    
    localized_labels = options[:localized_labels] ||= "en:#{property_name}"
    localized_labels_map = {}
    localized_labels.split(',').each {|loc_lab| loc_lab_array = loc_lab.split(':'); localized_labels_map[loc_lab_array[0]] = loc_lab_array[1]}
    
    type_specified = options.has_key? :type
    max_values_specified = options.has_key? :max_values
    min_values_specified = options.has_key? :min_values
    parent_specified = options.has_key? :parent
    type = options[:type] ||= 'string'
    max_values = options[:max_values] ||= '1'
    min_values = options[:min_values] ||= '0'
    parent = options[:parent]

    schema = nil
    File.open(schema_file, 'r') do |f|
      schema = Nokogiri::XML(f) do |config|
        config.noblanks
      end
    end
    
    
    # find if specified property is already defined
    property_node_set = schema.xpath "//xs:element[@name='#{property_name}']"
    if property_node_set.length == 0  # property is not defined
      # if a parent has been specified check if it exists
      error <<-MSG if parent && schema.xpath("//xs:element[@name='#{parent}']").length == 0
      The parent property '#{parent}' you specified does not exist. 
      Please check the XML Schema at '#{schema_file}' and run the command again with a
      existing parent property.
      MSG
      display "property '#{property_name}' is not yet defined. Lets create it..."
      property = create_property schema, object_type: object_type, name: property_name, 
        type: type, min_values: min_values, max_values: max_values, i18n: localized_labels_map
        
      write_xml schema, schema_file
      display <<-MSG
      Create new property '#{property_name}' for object type '#{object_type}': OK
      The new property is now defined in file: #{schema_file}
      The xml schema definition for the new property is: 
      #{property.to_xml indent: 1, indent_text: "\t", encoding: 'UTF-8'}
      MSG
    else
      display "property '#{property_name}' is already defined. Lets update it..."
      error "property update is not yet supported"
    end
  end
  
  
private

  def create_property schema, options
    object_type = options[:object_type]
    property = Nokogiri::XML::Node.new 'element', schema
    property['name'] = options[:name]
    property['minOccurs'] = options[:min_values]
    property['maxOccurs'] = options[:max_values]
    type = xsd_type options[:type]
    if type
      property['type'] = type
    else # complex properties do not have type but they need some more child tags
      property = to_complex schema, property
    end
    
    # add localized labels for property name
    localize schema, property, options[:i18n]
    
    # append the new property in XML Schema
    parent_node = schema.xpath("//xs:element[@name='#{object_type}']//xs:sequence").first
    error <<-MSG unless parent_node
    Could not locate the child '<xs:sequence>' tag inside '<xs:element name="#{object_type}"'
    in order to append the new property.
    If you have manually created the XML Schema file for object type '#{object_type}'
    then make sure that you have also created an empty '<xs:sequence></xs:sequence>' child tag 
    before using this command to add new properties.
    MSG
    parent_node << property
    property
  end
  
  
  def localize schema, element, localized_labels_map
    localized_labels_map.each do |locale, label|
      annotation_node = Nokogiri::XML::Node.new 'annotation', schema
      documentation_node = Nokogiri::XML::Node.new 'documentation', schema
      documentation_node["xml:lang"] = locale
      
      # here we need to add the astroboa namespace so lets find it in schema
      astroboa_namespace = schema.root.namespace_definitions.find{|ns| ns.prefix=="astroboa"}
      error <<-MSG unless astroboa_namespace
      Could not find the astroboa model namespace using namespace prefix 'astroboa'.
      If you have manually created the XML Schema make sure that you have specified 
      (inside the <xml:schema> tag) the astroboa model namespace with the proper prefix as follows:
        xmlns:astroboa="http://www.betaconceptframework.org/schema/astroboa/model"
      MSG
      display_name_node = Nokogiri::XML::Node.new 'displayName', schema
      display_name_node.namespace = astroboa_namespace
      display_name_node.content = label
      
      documentation_node << display_name_node
      annotation_node << documentation_node
      element << annotation_node
    end
  end
  
  
  def to_complex schema, property
    complex_type_node = Nokogiri::Node.new 'xs:complexType', schema
    sequence_node = Nokogiri::Node.new 'xs:sequence', schema
    complex_type_node.add_child sequence_node
    property.add_child complex_type_node
  end
  
  
  def xsd_type type
    type = case type
    when 'string';      'xs:string'
    when 'integer';     'xs:int'
    when 'double';      'xs:double'
    when 'boolean';     'xs:boolean'
    when 'date';        'xs:date'
    when 'dateTime';    'xs:dateTime'
    when 'binary'
      
    when 'topic_ref'
      
    when 'object_ref';  'astroboa:contentObjectReferenceType'
    when 'complex';     nil
    else type
    end
  end
  
  
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
      
      unless errors.empty?
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
        puts 'Check if domain model properly loads and uses external schemas (i.e. astroboa model schemas + user defined schemas): OK'
        true
      rescue => e
        puts 'Check if domain model is properly loading and using external schemas (i.e. astroboa model schemas + user defined schemas): Errors found!'
        puts external_schemas_validator.errors if external_schemas_validator
        puts e.message
        false
      end

    end

  end

end