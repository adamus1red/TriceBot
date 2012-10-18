 package Trice;
 use lib './plugins';

 use strict;
 use warnings;
 use POE qw(Component::IRC); 
 use POE::Component::IRC::State;
 use POE::Component::IRC::Common;
 use POE::Component::IRC::Plugin;
 use POE::Component::IRC::Plugin::Connector;
 use POE::Component::IRC::Plugin::CTCP;
 use POE::Component::IRC::Plugin::NickServID;
 use POE::Component::IRC::Plugin::NickReclaim;
 use POE::Component::IRC::Plugin::AutoJoin;
 use POE::Component::IRC::Plugin::BotTraffic;
 use POE::Component::IRC::Plugin::Logger;
 use DBI;
 use LWP::Simple;
 use Config::Simple;
 use Class::Unload;
 use Module::Refresh;
 use Log::Log4perl qw(get_logger);

 my $conf_file = "bot.cfg";
 
 my $cfg = new Config::Simple();
 $cfg->read($conf_file) or die "CONFIG ERROR: ".$cfg->error();
 
 # Initialize logging
 Log::Log4perl::init($conf_file);
 my $logger = Log::Log4perl->get_logger("Trice::Log");

 # IRC Config
 my $nickname = $cfg->param('irc_nick');
 my $ircname = $cfg->param('irc_name');
 my $server = $cfg->param('irc_server');
 my $pass = $cfg->param('irc_nickpass');
 my $use_oper = $cfg->param('use_oper');
 my $operuser = $cfg->param('oper_user');
 my $operpass = $cfg->param('oper_pass');
 
 #Channels
 my $mainchan = $cfg->param('admin_chan');
 my @channels = $cfg->param('channels');
 
 #MySQL Config
 my $sqluser = $cfg->param('sql_user');
 my $sqlpass = $cfg->param('sql_pass');
 my $sqldb = $cfg->param('sql_db');
 my $sqltable = $cfg->param('sql_table');
 my $db;
 if($cfg->param("use_sql")){
	$db = sql_connect($sqluser, $sqlpass, $sqldb);
 }
 
 #Bot Stuff
 my $version = "0.1";
 my $bot_admin = $cfg->param('bot_admins');
 my @official_plugins = qw(DCC ISupport Whois Connector Blowfish Thanks CTCP NickServID NickReclaim AutoJoin Magic8Ball BotTraffic Logger Hailo);
 
 #MySQL Functions
 sub sql_connect;
 sub sql_disconnect;
 
 # We create a new PoCo-IRC object
 my $irc = POE::Component::IRC->spawn(
	alias => 'trice',
    nick => $nickname,
    ircname => $ircname,
	username => $ircname,
    server => $server,
	flood => 1,
	raw => 0,
 ) or die "Oh noooo! $!";
 
 POE::Session->create(
     package_states => [
         Trice => [ qw(_default _start irc_001 irc_public irc_433 lag_o_meter irc_plugin_error) ],
     ],
     heap => { irc => $irc },
 );
 
 $poe_kernel->run();
 
 sub _start {
     my ($kernel, $heap) = @_[KERNEL ,HEAP];
     # retrieve our component's object from the heap where we stashed it
     my $irc = $heap->{irc};
	 
	 $logger->info("Starting up.");
	 $logger->info(get_version_string());
	 
     $irc->yield( register => 'all' );

	 $heap->{connector} = POE::Component::IRC::Plugin::Connector->new('reconnect' => '10');
     $irc->plugin_add( 'Connector' => $heap->{connector} );
	 
	 # CTCP Reply
	 $irc->plugin_add( 'CTCP' => POE::Component::IRC::Plugin::CTCP->new(
         version => \&get_version_string(),
         userinfo => \&get_version_string(),
		 clientinfo => \&get_version_string(),
     ));
	 
	 # NickServ Plugin.
	  $irc->plugin_add( 'NickServID', POE::Component::IRC::Plugin::NickServID->new(Password => $cfg->param('irc_nickpass')));
	  
	 # Nick Recplaim - keep trying to get the nick if someone else has it.
	 $irc->plugin_add( 'NickReclaim' => POE::Component::IRC::Plugin::NickReclaim->new( poll => 30 ) );
	 
	 # AutoJoin Some chans and stuff
	 $irc->plugin_add('AutoJoin', POE::Component::IRC::Plugin::AutoJoin->new( Channels => \@channels, RejoinOnKick => '1', Rejoin_delay => '1' ));
	 
	 # BotTraffic - a module that displays any traffic the bot does.
	 $irc->plugin_add( 'BotTraffic', POE::Component::IRC::Plugin::BotTraffic->new() );
	 
	 # Logger - Logs all server text (channel/privmsg/notice) - This is seperate to the error logging log4perl does
     $irc->plugin_add('Logger', POE::Component::IRC::Plugin::Logger->new(Path =>'logs/chat/',Private => 0,Public => 1,DCC => 0, ));
	 
     $irc->yield ( connect => { Nick => $nickname, Server => $server } );
     $kernel->delay( 'lag_o_meter' => 60 );

     return;
 }
 
 sub irc_001 {
     my $sender = $_[SENDER];
     # Since this is an irc_* event, we can get the component's object by accessing the heap of the sender. Then we register and connect to the specified server.
     my $irc = $sender->get_heap();
	 $logger->info("Connected to ".$irc->server_name());
	 if($cfg->param('debug')){
		$irc->yield(debug => 1);
	 }

	 join_channels();
	 
	 my @plugins = $cfg->param('plugins');
	 foreach(@plugins){ my $plugin = $_; load_plugin($plugin); }

	 $irc->yield(privmsg => $mainchan => "Loaded Plugins: ".get_loaded_plugins());
	 $irc->yield(privmsg => $mainchan => get_version_string());
	 
     return;
 }
 
  sub lag_o_meter {
     my ($kernel,$heap) = @_[KERNEL,HEAP];
     #print 'Time: ' . time() . ' Lag: ' . $heap->{connector}->lag() . "\n";
     $kernel->delay( 'lag_o_meter' => 60 );
     return;
 }
 
 sub irc_433 {
	$irc->yield(nick => $nickname."_");
	$irc->yield(privmsg => nickserv => "GHOST $nickname $pass");
	$irc->yield(nick => $nickname);	
	join_channels();
 }
 
 sub irc_public {
     my ($sender, $who, $where, $what) = @_[SENDER, ARG0 .. ARG2];
     my $nick = ( split /!/, $who )[0];
     my $channel = $where->[0];
	 my $message = Trice::clean($what);
	 
	
	 my $admin_users = join ('|', $cfg->param("bot_admins"));
	 if($nick =~ m/($admin_users)/i){
		 if($message =~ /^\.reload/i){
			my $plugin;
			my $answer = "0";
			my $output;
			my $off_plugins = join ('|', @official_plugins);
			my @aliases = keys %{ $irc->plugin_list() };
			Module::Refresh->refresh;
			if($message =~ /^\.reload (\w+)/i){
				my $reload = $1;
				foreach(@aliases){
					if($_ =~ /^$reload$/){
						reload_plugin($reload, $channel);
						$answer = "1";
					}
				}
				if($answer eq "0"){
					$output = "Plugin not found, Available Plugins: ".get_loaded_plugins();
					$irc->yield(privmsg => $channel => $output);
				}
			} else {
				foreach(@aliases){
					my $plugin_alias = $_;
					$plugin_alias =~ s/2//g;
					if($_ !~ m/($off_plugins)/i){ 
						reload_plugin($plugin_alias, $channel);
					}	
				}
			}
		}
		elsif($message =~ /^\.load (\S+)/i){
			if(load_plugin($1)){ $irc->yield(privmsg => $channel => "Loaded Plugin: $1"); }
		}
		elsif($message =~ /^\.unload (\S+)/i){
			if(unload_plugin($1)){ $irc->yield(privmsg => $channel => "Unloaded Plugin: $1"); }
		}
	}
	
	if($message =~ /^\!version/){ $irc->yield(privmsg => $channel => get_version_string()); }
    
	return;
 }
 
 # We registered for all events, this will produce some debug info.
 sub _default {
     my ($event, $args) = @_[ARG0 .. $#_];
	 my $arg;
	 if($event !~ /irc_raw/i){
		 my @output = ( "$event: " );
		 for my $arg (@$args) {
			 if ( ref $arg eq 'ARRAY' ) {
				 push( @output, '[' . join(', ', @$arg ) . ']' );
			 }
			 else {
				 push ( @output, "'$arg'" );
			 }
		 }
		 if($cfg->param('debug')){
			print join ' ', @output, "\n";
		 }
	 }
     return 0;
 }

 sub irc_plugin_error {
	 my($error) = $_[ARG0];
	 if($error){ 
		&Trice::output_error("PLUGIN ERROR: $error");
	}
 }
 
 sub clean {
	my $input = shift;
	return &POE::Component::IRC::Common::strip_color(&POE::Component::IRC::Common::strip_formatting($input));
 }
 
 sub sql_connect {
	my($user, $pass, $db) = @_;
	eval { 
		$db = DBI->connect("DBI:mysql:database=".$db.";host=localhost", $user, $pass,{
			'RaiseError' => 0, 
			'mysql_auto_reconnect'	=> 1, 
			'HandleError' => \&handle_sql_error,
			'PrintError' => 0,
			}
		); 
	};
	if($@){ 
		if($@ =~ /DBI connect.* failed\: (.*) at \S+ line \d+/i){
			&Trice::output_error("DBERROR: $1");
		} else {
			&Trice::output_error("DBERROR: $@");
		}
	} else {
		$logger->info("Connecting to SQL.");
	}
	return $db;
 }
 
 sub sql_disconnect {
	$db->finish();
	$db->disconnect();
	$logger->info("Disconnecting from SQL.");
}

sub handle_sql_error {
	my ($error, $handle, $return) = @_;
	output_error("DBERROR: $error");
}

 sub get_sql {
	 return $db;
 }
 
 sub output_error {
	 my ($error) = @_;
	 if($error){
		$logger->error($error);
		$irc->yield(privmsg => $mainchan => $error);
	 }
 }

 sub commify {
        my $input = shift;
        if($input eq ""){ return; }
        $input = reverse $input;
        $input =~ s<(\d\d\d)(?=\d)(?!\d*\.)><$1,>g;
        return reverse $input;
}

sub trim($){
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

 sub load_plugin {
	my($plugin) = @_;
	my $plugin_name = $plugin;
	eval { 
		require $plugin.".pm"; 
		$plugin = $irc->plugin_add( $plugin => "$plugin"->new() ); 
	};
	if($@){ 
		print $@;
		&Trice::output_error("Plugin Compile Error: $@");
		return 0;
	} else {
		$logger->info("Plugin Loaded: ".$plugin_name);
		return 1;
	}
 }
 
 sub unload_plugin {
	my($plugin) = @_;
	my $pg = $irc->plugin_del( $plugin );
	Class::Unload->unload("$plugin");
	$logger->info("Plugin Unloaded: $plugin");
 }
 
 sub reload_plugin {
	my($plugin_alias, $channel) = @_;
	my $plugin;
	unload_plugin($plugin_alias);
	load_plugin($plugin_alias);
	$plugin = $irc->plugin_get( $plugin_alias );
	$irc->yield( privmsg => $channel => "Reloaded Plugin: $plugin_alias");
 }
 
 sub get_loaded_plugins {
	 my @aliases = keys %{ $irc->plugin_list() };
	 my $loaded_plugins;
	 my $off_plugins = join ('|', @official_plugins);
	 foreach(@aliases){ if($_ !~ m/($off_plugins)/i){ $loaded_plugins .= $_.", "; } }
	 return $loaded_plugins = substr($loaded_plugins, 0, -2);
 }
 
 sub join_channels {
	 if($use_oper){
		$irc->yield(oper => $operuser => $operpass);
		# we join our channels
		foreach(@channels){
			$irc->yield( quote => "SAJOIN $nickname $_" );
			$logger->info("Joined channel: $_");
		}
	 } else {
		foreach(@channels){
			$irc->yield(join => $_);
			$logger->info("Joined channel: $_");
		}
	 }
 }

 sub convert_bytes { #Improved by MetalMichael
    my $bytes = shift;
    my $dec = shift;

    my $level = 0;
    my @levels = ("B","KB","MB","GB","TB");

    while ($bytes >= 1024 && $level < 4) {
        $bytes = $bytes / 1024;
        $level++;
    }

    $bytes =~ m/(\d+\.*\d{0,$dec})/;
    return $1 . " " . $levels[$level];
	
}

 my %usermap = ();
 sub get_mapped_user($) {
	my ($ircNick) = @_;
	# If we've got the nick mapped, return the site nick
	if(exists($usermap{$ircNick})) {
		return $usermap{$ircNick};
	}
	# Otherwise, default to the IRC nick
	return undef;
 }
 
 sub update_mapped_user($$) {
	my ($ircNick, $siteNick) = @_;
	if(!defined $siteNick) {
		delete($usermap{$ircNick});
	} else {
		$usermap{$ircNick} = $siteNick;
	}
 }
 
 sub get_version_string {
	return "Trice-Bot - Version: $version [perl ".substr($], 0, 4)."] [By AzzA] [http://red.broadcasthe.net/projects/trice]";
 }