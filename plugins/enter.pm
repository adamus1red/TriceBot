 package enter;

 use strict;
 use warnings;
 use POE::Component::IRC qw( :ALL );
 use POE::Component::IRC::Plugin qw( :ALL );
 use DBI;
 use Config::Simple;
 use Log::Log4perl qw(get_logger);
 my ($irc);
 my $db = &Trice::get_sql(); 
 my $logger = Log::Log4perl->get_logger("Trice::Log");
 
 my $cfg = new Config::Simple();
 $cfg->read('bot.cfg') or die $cfg->error();

 # Plugin object constructor
 sub new {
     my $package = shift;
     return bless {}, $package;
 }

 sub PCI_register {
     my ($self, $irc) = splice @_, 0, 2;

     $irc->plugin_register( $self, 'SERVER', qw(msg) );
     return 1;
 }

 # This is method is mandatory but we don't actually have anything to do.
 sub PCI_unregister {
     return 1;
 }

 sub S_msg {
     my ($self, $irc) = splice @_, 0, 2;

     # Parameters are passed as scalar-refs including arrayrefs.
     my $nick    = ( split /!/, ${ $_[0] } )[0];
     my $channel = ${ $_[1] }->[0];
     my $msg     = ${ $_[2] };
	 $msg = &Trice::clean($msg);
	 
	 if($msg =~ /^ENTER/i){
		 if($msg =~ /^ENTER (\S+) (\S+) (#\S+)$/i){
			 my $user = $1;
			 my $pass = $2;
			 my $request_chan = $3;
			 $logger->debug("Got 'ENTER' request from: $nick for channel: $request_chan"); # debug
			 my $query = "SELECT u.ID, 
                        u.Username, 
                        u.IRCKey, 
                        u.Enabled, 
                        p.name, 
                        p.Level
						FROM users_main AS u 
						JOIN permissions AS p ON u.PermissionID=p.ID
						JOIN users_info AS ui ON ui.UserID=u.ID
						WHERE Username = ? AND IRCKey = ?";
			 my $sql = $db->prepare($query);
			 $sql->execute($user, $pass);
			
			if ($sql->rows > 0) {
				 my ($user_id, $username, $irckey, $enabled, $class, $level) = $sql->fetchrow_array();
				 			 
				 if($enabled eq '1'){
					 $query = "SELECT Channel, Level FROM irc_channels WHERE Channel = ?";
					 my $sql = $db->prepare($query);
					 $sql->execute($request_chan);
					 my ($chan, $chan_level) = $sql->fetchrow_array();
					 if($chan and $chan_level ne ''){ 
						 if($level ge $chan_level) {
							if($cfg->param("use_oper")){
								$irc->yield(quote => "CHGIDENT $nick $user_id");
								$class =~ s/\s+//g;
								my $user_host = $username.".".$class.".".$cfg->param("site_url");
								$irc->yield(quote => "CHGHOST $nick $user_host");
								$irc->yield(quote => "SAJOIN $nick $chan");
								$logger->info ("Forced $nick to join $request_chan with ENTER command.");
							} else {
								$irc->yield(invite => $nick => $chan);
								$logger->info("Invited $nick to join $request_chan with ENTER command.");
							}
						 } else {
							 $irc->yield(privmsg => $nick => "Access Denied.");
							 $logger->warn("Access denied for user: $nick trying to join $request_chan with ENTER command.");
						 }
					 } else {
						$irc->yield(privmsg => $nick => "$request_chan not found in the channel list.");
					 }
				 } else {
					 $irc->yield(privmsg => $nick => "Your account is disabled.");
				 }
				 
			 } else {
				 $irc->yield(privmsg => $nick => "Wrong username and/or IRC key");
			 }	  
		 } else {
			$irc->yield(privmsg => $nick => "Invalid syntax: Username, IRC key and Channel required. Example: /msg ".$cfg->param('irc_nick')." ENTER <username> <irckey> <#chan>");
		 }
		 return PCI_EAT_ALL;
	 }
	 
     return PCI_EAT_NONE;
 }
 

 
 1;