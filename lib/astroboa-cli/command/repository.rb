# encoding: UTF-8

require 'astroboa-cli/command/base'
require 'fileutils'
require 'nokogiri'
#require 'arjdbc'
require 'pg'

# create, delete, backup, restore repositories
class AstroboaCLI::Command::Repository < AstroboaCLI::Command::Base
  
  # repository:create REPOSITORY_NAME
  #
  # Creates a new astroboa repository with the provided 'REPOSITORY_NAME'.
  # The 'REPOSITORY_NAME' is the internal repository name. 
  # It should be at least 3 characters long and should not contain spaces and special symbols (!#@?-*). 
  # Only english word characters are allowed (a-z or A-Z or 0-9 or _)
  # You may use the -l option to provide friendly localized (for different languages) labels with spaces
  # A directory named after the name of the new repository will be created to store repository configuration, indexes and blobs. 
  # This directory will be created under the global repositories directory that has been setup during astroboa server installation.
  # A database will also be created to store repository data (except blobs).
  # The database server, db user and db password that have been configured during astroboa server setup will be used.   
  #
  # -l, --localized_labels REPO_LABELS      # Provide friendly labels for different languages # By default the 'REPOSITORY_NAME' will be used as the english label # Example: -l en:Dali Paintings,fr:Dali Peintures,es:Dali Pinturas
  # -d, --domain_name REPO_DOMAIN_NAME      # Specify the fully qualified domain name and port under which all the repository resources will be exposed by the REST API # The default is 'localhost:8080' # If you specify other than the default (e.g. www.mydomain.com) you need to appropriately setup a reverse proxy in front of astroboa 
  # -p, --api_base_path REST_API_BASE_PATH  # Specify the base_path of the REST API URLs # The default is '/resource-api' # If you provide other than the default you should appropriately setup a reverse proxy in front of astroboa
  # -n, --db_name DATABASE_NAME             # Specify the name of the database to create # Default is REPOSITORY_NAME (i.e. the name of the new repository)
  #
  #Examples:
  #
  # Create the repository 'dali_paintings'. 
  # It will be stored in db named 'dali_paintings' and its RESOURCES 
  # will be available under http://localhost:8080/resource-api/dali_paintings
  # $ astroboa-cli repository:create dali_paintings
  #
  # Specify i18n labels for the repository name.
  # Expose the repo resources under http://www.art.com/art-api/dali_paintings
  # $ astroboa-cli repository:create dali_paintings -l en:Dali Paintings,fr:Dali Peintures,es:Dali Pinturas -d www.art.com -p art-api
  #
  def create
    
    if repository_name = args.shift
      repository_name = repository_name.strip
    else
      error "Please specify the repository name. Usage: repository:create REPOSITORY_NAME"
    end
    error "Please use at least 3 english word characters (a-zA-Z0-9_) without spaces for the repository name" unless repository_name =~ /^\w{3,}$/
  
    server_configuration = get_server_configuration
    
    check_repo_existense(server_configuration, repository_name)
    
    database_name = options[:db_name] ||= repository_name
    
    begin
      astroboa_dir = server_configuration['install_dir']
      repos_dir = server_configuration['repos_dir']
      
      # if OS is linux or [OS is mac and repos_dir is not writable by current user] 
      # then astroboa-cli should run with sudo in order to have the required privileges to write files
      check_if_running_with_sudo if linux? || (mac_os_x? && !dir_writable?(repos_dir))
      
      repo_dir = File.join(repos_dir, repository_name)
      FileUtils.mkdir_p(repo_dir)
      display "Create repository dir '#{repo_dir}': OK"
    
      schema_dir = File.join(repo_dir, "astroboa_schemata")
      FileUtils.mkdir(schema_dir)
      display %(Create dir '#{schema_dir}': OK)
      
      # This is not required any more TO BE DELETED
      #internal_repo_dir = File.join(repo_dir, "repository")
      #FileUtils.mkdir(internal_repo_dir)
      #display %(Create dir '#{internal_repo_dir}': OK)
    
      # create postgres database
      unless server_configuration['database'] == 'derby'
        begin
          create_postgresql_db(server_configuration, database_name)
        rescue
          FileUtils.rm_r repo_dir, :secure=>true
          error "Removing #{repo_dir} and Exiting..."
        end
      end
    
      # config jcr repository (create repository.xml)
      configure_jcr_repo(server_configuration, astroboa_dir, repo_dir, repository_name, database_name)
    
      # config astroboa repository (create configuration in repositories-conf.xml)
      configure_astroboa_repo(astroboa_dir,repos_dir, repo_dir, repository_name)
      
      # save repo configuration into astroboa server config file
      add_repo_conf_to_server_conf(server_configuration, repository_name)
       
    rescue Exception => e
      display %(An error has occured \n The error is: '#{e.to_s}' \n The error trace is: \n #{e.backtrace.join("\n")})
      display %(Repository configuration, the db and the related directories will be removed)
      unconfigure_astroboa_repo(repos_dir, repository_name)
      FileUtils.rm_r repo_dir, :secure=>true
      display "Remove #{repo_dir} : OK"
      drop_postgresql_db(server_configuration, database_name) if server_configuration['database'] =~ /postgres/
      error 'Exiting...'
    end

  end
  
  
  # repository:delete REPOSITORY_NAME
  #
  # Unconfigures and deletes an existing astroboa repository named 'REPOSITORY_NAME'. 
  # BE VERY CAREFUL with this operation. All Repository configuration and data will be permanently lost. 
  # You are adviced to use the repository:backup command before deleting a repository in the case that you would like to recover it back.
  # If you just want to disable the repository use the repository:disable / repository:enable commands
  # The 'REPOSITORY_NAME' is the internal repository name. 
  # To find which repositories are available and see their internal names use the repository:list command
  #
  # -f, --force # Use this option if you wish to enforce the removal of the 'identities' repository # You must have already removed all other repositories before enforcing the 'identities' removal    
  #
  def delete
    if repository_name = args.shift
      repository_name = repository_name.strip
    else
      error "Please specify the repository name. Usage: repository:delete REPOSITORY_NAME"
    end
    
    server_configuration = get_server_configuration
    
    repos_dir = server_configuration["repos_dir"]
    
    # if OS is linux or [OS is mac and repos_dir is not writable by current user] 
    # then astroboa-cli should run with sudo in order to have the required privileges to remove files
    check_if_running_with_sudo if linux? || (mac_os_x? && !dir_writable?(repos_dir))
    
    # check if repo exists
    repo_dir = File.join(repos_dir, repository_name)
    error "Repository #{repository_name} does not exist in directory #{repo_dir}" unless File.exists? repo_dir
    error %(Repository #{repository_name} does not exist in astroboa server configuration file "#{get_server_conf_file}") unless repository_in_server_config?(server_configuration, repository_name) 
    
    # we treat 'identities' repo very carefully
    if repository_name == 'identities'
      error "You must remove all other repositories before removing the 'identities' repository" if server_configuration['repositories'].keys.length > 1
      error "Use the '--force' option if you want to remove the identities repository" unless options[:force]
    end
    
    # first stop serving the repository
    unconfigure_astroboa_repo(repos_dir, repository_name)
    
    # remove dir with indexes, blobs and schemas 
    FileUtils.rm_r repo_dir, :secure=>true
    display "Remove #{repo_dir} : OK"
    
    # remove repo conf from astroboa server configuration
    delete_repo_conf_from_server_conf(server_configuration, repository_name)
    
    # remove the repo database, we leave it last so that everything else has been removed in the case something goes wrong
    # with db removal
    begin
      drop_postgresql_db(server_configuration, database_name) if server_configuration['database'] =~ /postgres/
    rescue
      display %(The repository has been disabled and all configuration and related directories have been removed except the database.)
      display %(It is safe to manually remove the database)
    end
      

  end
  
  
  def disable
    
  end
  
  
  def enable
    
  end
  
  # repository:list REPOSITORY_NAME
  #
  # Lists the available repositories. If the name of an existing repository is provided it displays information about the repository.   
  #
  def list
    server_configuration = get_server_configuration
    repos_dir = server_configuration["repos_dir"]
    
    if repository_name = args.shift
      repository_name = repository_name.strip
      
      # check if repo exists
      error %(Repository #{repository_name} does not exist") unless repository_in_server_config?(server_configuration, repository_name)
      repo = server_configuration['repositories'][repository_name]
      display "Repository Name:                 #{repo['id']}"
      repo['localized_labels'].split(',').each do |localized_label|
        locale, label = localized_label.split(':')
        display "Label for locale '#{locale}':            #{label}"
      end
      display "Authentication Token Timeout:    #{repo['authenticationTokenTimeout']}"
      display "Domain of Generated URLs:        #{repo['serverAliasURL']}"
      display "REST API Base Path:              #{repo['restfulApiBasePath']}"
    else
      server_configuration['repositories'].each do |repo_name, repo_conf|
        display "Repository Name:           #{repo_name}"
      end
    end
    
  end
  
  def backup
    
  end
  
  
  def populate
    
  end
  
private
  
  def configure_jcr_repo(server_configuration, astroboa_dir, repo_dir, repository_name, database_name)
    database = server_configuration['database']
    database_admin = server_configuration['database_admin']
    database_admin_password = server_configuration['database_admin_password']
    database_server = server_configuration['database_server']
    
    datasource_user = database_admin
    datasource_password = database_admin_password
    
    datasource_driver = 'org.postgresql.Driver'
    datasource_url = "jdbc:postgresql://#{database_server}:5432/#{database_name}"
    datasource_databaseType = 'postgresql'
    persistence_manager_class = 'org.apache.jackrabbit.core.persistence.pool.PostgreSQLPersistenceManager'
    
    if database == 'derby'
      derby_db_file = File.join(repo_dir, "#{database_name}_derby.db")
      datasource_driver = 'org.apache.derby.jdbc.AutoloadedDriver'
      datasource_url = "jdbc:derby:directory:#{derby_db_file};create=true"
      datasource_databaseType = 'derby'
      persistence_manager_class = 'org.apache.jackrabbit.core.persistence.pool.DerbyPersistenceManager'
    end
    
    repository_template = File.join(astroboa_dir, "astroboa-setup-templates", "repository-template.xml")
    jcr_repo_conf = File.join(repo_dir, "repository.xml")
    context = {
      :datasource_driver          =>  datasource_driver, 
      :datasource_url             =>  datasource_url,
      :datasource_databaseType    =>  datasource_databaseType,
      :datasource_user            =>  datasource_user,
      :datasource_password        =>  datasource_password,
      :persistence_manager_class  =>  persistence_manager_class
    }
    render_template_to_file(repository_template, context, jcr_repo_conf)
    display "Generating jcr repository configuration in #{jcr_repo_conf} : OK"
  end
  
  
  def configure_astroboa_repo(astroboa_dir,repos_dir, repo_dir, repository_name)
    repo_domain_name = options[:domain_name] ||= 'localhost:8080'
    api_base_path = options[:api_base_path] ||= '/resource-api'
    localized_labels = options[:localized_labels] ||= "en:#{repository_name}"
    localized_labels_map = {}
    localized_labels.split(',').each {|loc_lab| loc_lab_array = loc_lab.split(':'); localized_labels_map[loc_lab_array[0]] = loc_lab_array[1]}
    
    # repos config is kept in the repositories root directory
    astroboa_repos_config = File.join(repos_dir, "repositories-conf.xml")
    conf_exists = true
    unless File.exists? astroboa_repos_config
      conf_exists = false
      display %(Configuration file #{astroboa_repos_config} does not exist. Copying from templates...)
      astroboa_repos_config_template = File.join(astroboa_dir, "astroboa-setup-templates", "repositories-conf.xml")
      FileUtils.cp astroboa_repos_config_template, repos_dir
      display %(Copy #{astroboa_repos_config_template} to #{repos_dir} : OK)
    end
    
    repo_conf = nil
    File.open(astroboa_repos_config, 'r') do |f|
      repo_conf = Nokogiri::XML(f) do |config|
        config.noblanks
      end
    end
    
    repository = Nokogiri::XML::Node.new "repository", repo_conf
    repository['id'] = repository_name
    repository['repository-home-directory'] = repo_dir
    repository['authenticationTokenTimeout'] = "2880"
    repository['serverAliasURL'] = "http://#{repo_domain_name}"
    repository['restfulApiBasePath'] = api_base_path
    # All repositories use the 'identities' repository as a central store for user and app identities, i.e. for storing authentication / authorization data
    # The central 'identities' repository stores its own authentication / authorization data 
    repository['identity-store-repository-id'] = 'identities' unless repository_name == 'identities' 
    
    repo_conf.root << repository
    
    # delete namespace of repository node so that it will be serialized as 
    # <repository> instead of <ns:repository> which is not recognized by astroboa SAX parser
    repository.namespace = nil
    
    localization = Nokogiri::XML::Node.new "localization", repo_conf
    localized_labels_map.each do |locale, label|
      label_node = Nokogiri::XML::Node.new "label", repo_conf
      label_node['xml:lang'] = locale
      label_node.content = label
      localization << label_node
    end
    
    repository << localization
    
    security = Nokogiri::XML::Node.new 'security', repo_conf
    
    permanentUserKeyList = Nokogiri::XML::Node.new 'permanentUserKeyList', repo_conf
    permanentUserKey = Nokogiri::XML::Node.new 'permanentUserKey', repo_conf
    permanentUserKey['userid'] = 'anonymous,SYSTEM'
    permanentUserKey['key'] = 'permanentUserKey'
    permanentUserKeyList << permanentUserKey
    security << permanentUserKeyList
    
    secretUserKeyList = Nokogiri::XML::Node.new 'secretUserKeyList', repo_conf
    administratorSecretKey = Nokogiri::XML::Node.new 'administratorSecretKey', repo_conf 
    administratorSecretKey['userid'] = 'SYSTEM'
    administratorSecretKey['key'] = 'betaconcept'
    secretUserKeyList << administratorSecretKey
    security << secretUserKeyList
    
    repository << security
    
    jcrCache = Nokogiri::XML::Node.new 'jcrCache', repo_conf
    jcrCache['maxMemory'] = '384'
    jcrCache['maxMemoryPerCache'] = '32'
    jcrCache['minMemoryPerCache'] = '256'
    
    repository << jcrCache
    
    strip_text_nodes(repo_conf)
    new_astroboa_repos_config = "#{astroboa_repos_config}.new"
    File.open(new_astroboa_repos_config, 'w') do |f|
      repo_conf.write_xml_to(f, :indent => 1, :indent_text => "\t", :encoding => 'UTF-8')
    end
    
    # save old config file
    if conf_exists
      current_date = DateTime.now().strftime('%Y-%m-%dT%H.%M')
      FileUtils.cp astroboa_repos_config, "#{astroboa_repos_config}.#{current_date}"
      display %(Save previous repositories configuration file to #{astroboa_repos_config}.#{current_date} : OK)
    end
    
    FileUtils.mv new_astroboa_repos_config, astroboa_repos_config
    display %(Created new repositories configuration file #{astroboa_repos_config})
  end
  
  
  def unconfigure_astroboa_repo(repos_dir, repository_name)
    display "Removing configuration of repository #{repository_name} from repositories configuration file..."
    astroboa_repos_config = File.join(repos_dir, "repositories-conf.xml")
    if File.exists? astroboa_repos_config
      repo_conf = nil
      File.open(astroboa_repos_config, 'r') do |f|
        repo_conf = Nokogiri::XML(f) do |config|
          config.noblanks
        end
      end
      
      repo_nodes = repo_conf.xpath(%(//repository[@id="#{repository_name}"]))
      
      if !repo_nodes.empty?
        repo_nodes.remove
        strip_text_nodes(repo_conf)
        new_astroboa_repos_config = "#{astroboa_repos_config}.new"
        File.open(new_astroboa_repos_config, 'w') do |f|
          repo_conf.write_xml_to(f, :indent => 1, :indent_text => "\t", :encoding => 'UTF-8')
        end
      
        current_date = DateTime.now().strftime('%Y-%m-%dT%H.%M')
        FileUtils.cp astroboa_repos_config, "#{astroboa_repos_config}.#{current_date}"
        display %(Save previous repositories configuration file to #{astroboa_repos_config}.#{current_date} : OK)
      
        FileUtils.mv new_astroboa_repos_config, astroboa_repos_config
        display %(Unconfigure repository #{repository_name} : OK)
      else
        display "WARNING: configuration settings for repository '#{repository_name}' do not exist in repositories configuration file: '#{astroboa_repos_config}'"
        display "You may ignore the above warning if you tried to create a new repo and an error has occured before its creation."
      end
    else
      error "cannot find repositories configuration file: '#{astroboa_repos_config}'"
    end
  end
  
  
  # remove leading and trailing white space from XML Document text nodes
  def strip_text_nodes(xml_doc)
    xml_doc.traverse do |node|
      if node.text?
        node.content = node.content.strip
      end
    end
  end
  
  
  def add_repo_conf_to_server_conf(server_configuration, repository_name)
    repo_domain_name = options[:domain_name] ||= 'localhost:8080'
    api_base_path = options[:api_base_path] ||= '/resource-api'
    localized_labels = options[:localized_labels] ||= "en:#{repository_name}"
    
    server_configuration['repositories'] ||= {}
    repository = {}
    repository['id'] = repository_name
    repository['authenticationTokenTimeout'] = '2880'
    repository['serverAliasURL'] = "http://#{repo_domain_name}"
    repository['restfulApiBasePath'] = api_base_path
    repository['localized_labels'] = localized_labels
    server_configuration['repositories'][repository_name] = repository
    save_server_configuration(server_configuration)
    display "Add repository configuration to server configuration file '#{get_server_conf_file}' : OK"
  end
  
  
  def delete_repo_conf_from_server_conf(server_configuration, repository_name)
    if repository_in_server_config?(server_configuration, repository_name)
      server_configuration['repositories'].delete(repository_name)
      save_server_configuration(server_configuration)
      display "Remove configuration settings for repository '#{repository_name}' from server settings file : OK"
    else
      display "No configuration found in server configuration file for repository '#{repository_name}'"
    end
  end
  
  def check_repo_existense(server_configuration, repository_name)
    repos_dir = server_configuration['repos_dir']
    repo_dir = File.join(repos_dir, repository_name)
    error "Repository #{repository_name} already exists in directory #{repo_dir}" if File.exists? repo_dir
    error "Creation failed. A configuration for repository '#{repository_name}' exists in repositories configuration file (#{File.join(repos_dir, 'repositories-conf.xml')})" if repository_in_repos_config? repos_dir, repository_name
    error "Creation failed. A configuration for repository '#{repository_name}' exists in server configuration file (#{get_server_conf_file})" if repository_in_server_config?(server_configuration, repository_name)
  end
  
end # class Repository 
