# astroboa-cli

The astroboa-cli gem provides a command line interface to astroboa platform and astroboa apps management.  

It has easy to use commands for installing astroboa platform, creating new repositories, taking backups and deploying your ruby apps directly to astroboa.


## Prerequisites
* Linux or MAC OS X operating system. Windows is not yet supported

* BUILD TOOLS: 
	* In MAC OS X is strongly recommended to install 'brew' package manager as well as XCODE 
		and XCODE command line tools in order to be able to compile new packages and ruby native extensions.
	* If you're running Ubuntu, you must install the build-essential package (apt-get install build-essential) 
		because some required gems (nokogiri, pg) build native extensions and require the make utility.

* Java 1.6.x is required for running astroboa server. 
	* If you consider a production system use **Sun/Oracle JDK**. For testing/development **OpenJDK** can be ok but we have not exhaustively tested it.  
	* On **MAC OS X up to Lion** java 1.6 is  pre-installed. On Mountain Lion (even in upgrades) java is not installed. 
		To install java 1.6 on **Mountain Lion** open a terminal and run: `java -version`. A window will pop-up prompting you to: 'install Java SE in order to open "java"', click "Install" to get the latest version.
	* On **Ubuntu Linux** there might be a problem to find packages for java 6 due to new Oracle licencing terms. 
		So either install the OpenJDK package or check https://github.com/flexiondotorg/oab-java6 to find how to create a local `apt` repository for Sun Java 6 
	
* Ruby 1.9.x is required for installing/running `astroboa-cli` itself. 
	If you need to install or upgrade your ruby read the following section on 'how to install ruby'. 

* libxml2 and libxslt.
	astroboa-cli uses `nokogiri` gem which depends on `libxml2` and `libxslt`.
	* On **MAC OS X** you do not need to install anything if you already have installed the latest XCODE (this needs some verification) 
	* On **Ubuntu Linux** run: `sudo apt-get install libxslt-dev libxml2-dev`.
		For more info on how to install libxml2 and libxslt on different linux distros or mac os x read http://nokogiri.org/tutorials/installing_nokogiri.html
	
* OPTIONAL Postgres Gem: 
	You should manually install `pg` gem if you want to install/setup astroboa to work with postgres database.
	If you do not specify a database during astroboa installation then `derby db` is used which is the best option for testing and development. 
	If you are ok with derby db then you do not need to install the 'pg' gem.
	If you want to set up a production environment then choose postgres db during astroboa installation. 
	In this case you should first manually install the 'pg' gem.
	astroboa-cli gem does not automatically install 'pg' gem since in some environments (e.g. MAC OS X) this might require to have a local postgres already installed which in turn is too much if you do not care about postgres.
	
	* In **Ubuntu Linux** run first `sudo apt-get install libpq-dev` and then run `gem install pg`.
	* For **MAC OS X** read http://deveiate.org/code/pg/README-OS_X_rdoc.html to learn how to install the `pg` gem.


## Install astroboa-cli gem in your ruby environment

After you have checked that prerequisites are met run at the command prompt:

	$ gem install astroboa-cli
 
To see the available commands:

	$ astroboa-cli help

To get help for a particular command:

	$ astroboa-cli help <command>

e.g. astroboa-cli help server

To get help for a particular subcommand:

	$ astroboa-cli help <command:subcommand>

e.g.  `$ astroboa-cli help server:install`


### NOTE on running astroboa-cli with sudo:
If you use astroboa-cli in LINUX then server installation/running and repository installation/removal always require sudo privileges because astroboa is installed and runs as user 'astroboa'.
In MAC OS X no special user is created and thus sudo privileges are only required if you want to install astroboa to a directory that you do not own.
astroboa-cli checks the required privileges for each command and will produce an error message if not met. 

If your ruby is installed with `rbenv` then **you need to also install** the `rbenv-sudo` plugin to overcome the problem of using rbenv installed rubies with sudo.
With `rbenv-sudo` installed you can install astroboa with the following command:

	$ rbenv sudo astroboa-cli server:install

*Check the instructions on the following section about installing ruby to also learn how to install rbenv-sudo*

If you manage your rubies with `rvm` the you should use the `rvmsudo` command

	$ rvmsudo astroboa-cli server:install



# How to install ruby

astroboa-cli requires ruby version 1.9.x.
If you do not have ruby already installed or your operating system comes with an older version, here is some quick info on two easy ways to install and maintain your ruby environment.

You can easily install ruby with `rbenv` or `rvm` utility programs.

## Install Ruby with RBENV

We recommend to install ruby using the `rbenv` and `ruby-build` utility commands.

---
On **Mac OS X**  to install `rbenv` and `ruby-build` using the [Homebrew](http://mxcl.github.com/homebrew/) package manager do:

	$ brew update
	$ brew install rbenv
	$ brew install ruby-build
	$ echo 'if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi' >> ~/.bash_profile

The last command adds to your .bash_profile the code that initializes rbenv
	


---
On **Ubuntu Linux** to install `rbenv` and `ruby-build` using `apt` package manager and `git` do (it has been tested in Ubuntu 12.04):

	$ sudo apt-get install build-essential zlib1g-dev openssl libopenssl-ruby1.9.1 libssl-dev libruby1.9.1 libreadline-dev git-core
	$ cd
	$ git clone git://github.com/sstephenson/rbenv.git .rbenv


To make available `rbenv` commands to your shell add the following path to your `.bashrc`:
	
	$ echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc

To get automatic initialization of `rbenv` add the following line in your `.bashrc`:
	
	$ echo 'if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi' >> ~/.bashrc

Then install ruby-build:

	$ mkdir -p ~/.rbenv/plugins
	$ cd ~/.rbenv/plugins
	$ git clone git://github.com/sstephenson/ruby-build.git

---

**The folllowing instructions are the same for both MAC and Linux:**

To use `sudo` to run astroboa-cli (and any other ruby-based program) you should also install `rbenv-sudo`.
`rbenv` does not work with `sudo` due to sudo's 'secure_path' restriction. 
`rbenv-sudo` is a plugin for `rbenv` that allows you to run rbenv-provided Rubies and Gems from within a sudo session.

	$ git clone git://github.com/dcarley/rbenv-sudo.git ~/.rbenv/plugins/rbenv-sudo

After you have installed `rbenv`, `ruby-build` and optionally `rbenv-sudo` as described above do the following:

Restart your shell to apply the changes in your bashrc or bash_profile 

	$ exec $SHELL

To install ruby version 1.9.3-p286 do:

	$ rbenv install 1.9.3-p286
	$ rbenv rehash


*NOTE:* You should run `rbenv rehash` any time you install a new Ruby binary (for example, when installing a new Ruby version, or when installing a gem that provides a binary). So you should run `rbenv rehash` after you install astroboa-cli.

To set the global version of Ruby to be used in all your shells do:
	
	$ rbenv global 1.9.3-p286

To set ruby 1.9.3-p286 as a local per-project ruby version by writing the version name to an .rbenv-version file in the current project directory do:

	$ rbenv local 1.9.3-p286

To set ruby 1.9.3-p286 as the version to be used only in the current shell (sets the RBENV_VERSION environment variable in your shell) do:

	$ rbenv shell 1.9.3-p286

Test your ruby installation:

	$ rbenv global 1.9.3-p286
	$ ruby -v

On MAC you will get output similar to this: ruby 1.9.3p286 (2012-04-20 revision 35410) [x86_64-darwin12.0.0]

For more information about `rbenv`, `ruby-build` and `rbenv-sudo` check https://github.com/sstephenson/rbenv, https://github.com/sstephenson/ruby-build and https://github.com/dcarley/rbenv-sudo


## Install Ruby with RVM

If you prefer to use 'rvm' as your ruby management utility use the following command to install it for a single user:

	$ curl -L get.rvm.io | bash -s stable 

For multi-user installation and detailed rvm installation instructions check: https://rvm.io/rvm/install/
To use `sudo` to run astroboa-cli (and any other ruby-based program) you should use `rvmsudo`  

After 'rvm' has been installed run the following commands to install ruby 1.9.3-p286:

	$ rvm install 1.9.3-p286
	$ rvm use 1.9.3-p286
	
run: `$ rvm use 1.9.3-p286 --default` to make 1.9.3-p286 your default ruby

# LICENSE
-------
Released under the LGPL license; see the files LICENSE, COPYING and COPYING.LESSER. 

   

