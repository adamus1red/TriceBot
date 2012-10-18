 package announce;

 use strict;
 use warnings;
 use POE;
 use POE::Component::IRC qw( :ALL );
 use POE::Component::IRC::Plugin qw( :ALL );
 use POE::Component::Server::TCP;
 use POE::Filter::Line;
 use POE::Filter::Stream;
 use DBI;
 use Config::Simple;
 use Log::Log4perl qw(get_logger);
 my ($irc);
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

     $irc->plugin_register( $self, 'SERVER', qw() );
	 
	 # Store relevant info in our own hashref
	 $self->{SESSID} = POE::Component::Server::TCP->new(
	  	Alias       => "trice_controller",
	  	Port        => $cfg->param("socket_port"),
		Hostname => $cfg->param("socket_addr"),
	  	ClientInput => \&announce,
	 );
	 $self->{irc} = $irc;
	
	 # And increment the reference count for our new server session
	 $poe_kernel->refcount_increment($self->{SESSID}, __PACKAGE__);

     return 1;
 }

 # Shut down the TCP server when we unload
 sub PCI_unregister {
	 my ($self, $irc) = @_;
	
	# Send the shutdown event to the socket server
	$poe_kernel->call( $self->{SESSID} => '_shutdown' );
	delete $self->{irc};
	$poe_kernel->refcount_decrement($self->{SESSID}, __PACKAGE__);
	
     return 1;
 }
 
 sub announce {
	my ($session, $heap, $input) = @_[SESSION, HEAP, ARG0];
	print "Session ", $session->ID(), " got input: $input\n";
	
	$poe_kernel->post( trice => quote => $input );
 }
 

 1;