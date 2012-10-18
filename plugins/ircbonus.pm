 package ircbonus;

 use strict;
 use warnings;
 use POE;
 use POE::Component::IRC qw( :ALL );
 use POE::Component::IRC::Plugin qw( :ALL );
 use DBI;
 use Config::Simple;
 use Log::Log4perl qw(get_logger);
 my ($irc, $sql);
 my $db = &Trice::get_sql(); 
 my $logger = Log::Log4perl->get_logger("Trice::Log");
 
 my $cfg = new Config::Simple();
 $cfg->read('bot.cfg') or die $cfg->error();

 # Plugin object constructor
 sub new {
     my $package = shift;
     return bless {@_}, $package;
 }

 sub PCI_register {
     my ($self, $irc) = splice @_, 0, 2;

     $irc->plugin_register( $self, 'SERVER', qw(part join quit nick) );

     return 1;
 }

 sub PCI_unregister {
	 my ($self, $irc) = @_;	
     return 1;
 }
 
 sub S_part {
	my ($self, $irc) = splice @_, 0, 2;
	# Parameters are passed as scalar-refs including arrayrefs.
	my $nick	= ( split /!/, ${ $_[0] } )[0];
	my $channel = ${ $_[1] };
	 
	if($channel eq $cfg->param("irc_chan_main")){
		 $sql = $db->prepare("SELECT Username FROM users_main WHERE Username LIKE ?");
		 $sql->execute($nick);
		 if ($sql->rows > 0) {
			$db->do("UPDATE users_main SET onirc = 'no' WHERE username = ?", undef, $nick);
			$irc->yield(notice => $nick => "User Offline: \002$nick\002 - IRC bonus disabled.");
		 }
		 return PCI_EAT_ALL;
	}
	
	# Default action is to allow other plugins to process it.
	return PCI_EAT_NONE;
}

 sub S_join {
	my ($self, $irc) = splice @_, 0, 2;
	# Parameters are passed as scalar-refs including arrayrefs.
	my $nick	= ( split /!/, ${ $_[0] } )[0];
	my $channel = ${ $_[1] };
	 
	if($channel eq $cfg->param("irc_chan_main")){
		 $sql = $db->prepare("SELECT Username FROM users_main WHERE Username LIKE ?");
		 $sql->execute($nick);
		 if ($sql->rows > 0) {
			$db->do("UPDATE users_main SET onirc = 'yes' WHERE username = ?", undef, $nick);
			$irc->yield(notice => $nick => "User Online: \002$nick\002 - IRC bonus enabled.");
            $irc->yield(mode => $channel => "+v $nick");
		 }
		 return PCI_EAT_ALL;
	}
	
	# Default action is to allow other plugins to process it.
	return PCI_EAT_NONE;
 }
 
 sub S_nick {
	my ($self, $irc) = splice @_, 0, 2;
	# Parameters are passed as scalar-refs including arrayrefs.
	my $nick	= ( split /!/, ${ $_[0] } )[0];
	my $newnick = ${ $_[1] };


	 $sql = $db->prepare("SELECT Username FROM users_main WHERE Username LIKE ?");
	 $sql->execute($newnick);
	 if ($sql->rows > 0) {
		$db->do("UPDATE users_main SET onirc = 'yes' WHERE username = ?", undef, $newnick);
		$irc->yield(notice => $newnick => "User Online: \002$newnick\002 - IRC bonus enabled.");
		$irc->yield(mode => $cfg->param("irc_chan_main") => "+v $newnick");
	 } else {
		 $sql = $db->prepare("SELECT Username FROM users_main WHERE Username LIKE ?");
		 $sql->execute($nick);
		 if ($sql->rows > 0) {
			$db->do("UPDATE users_main SET onirc = 'no' WHERE username = ?", undef, $nick);
			$irc->yield(notice => $newnick => "User Offline: \002$newnick\002 - IRC bonus disabled.");
			$irc->yield(mode => $cfg->param("irc_chan_main") => "-v $newnick");
		 } 
	 }
	 return PCI_EAT_ALL;
	
 }
 
 sub S_quit {
	my ($self, $irc) = splice @_, 0, 2;
	# Parameters are passed as scalar-refs including arrayrefs.
	my $nick	= ( split /!/, ${ $_[0] } )[0];
	
	 $sql = $db->prepare("SELECT Username FROM users_main WHERE Username LIKE ?");
	 $sql->execute($nick);
	 if ($sql->rows > 0) {
		$db->do("UPDATE users_main SET onirc = 'no' WHERE username = ?", undef, $nick);
	 }
	 return PCI_EAT_ALL;
 }

 1;