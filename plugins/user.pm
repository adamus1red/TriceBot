 package user;

 use strict;
 use warnings;
 use POE::Component::IRC qw( :ALL );
 use POE::Component::IRC::Plugin qw( :ALL );
 use DBI;
 use Config::Simple;
 my $irc;
 
 #get the DB process for the plugin.
 my $db = &Trice::get_sql(); 
 #use the logger process for the plugin
 my $logger = Log::Log4perl->get_logger("Trice::Log");
 #parse the config for the plugin
 my $cfg = new Config::Simple();
 $cfg->read('bot.cfg') or die $cfg->error();
 my $url = $cfg->param("site_url");

 # Plugin object constructor
 sub new {
     my $package = shift;
     return bless {}, $package;
 }

 sub PCI_register {
     my ($self, $irc) = splice @_, 0, 2;

     $irc->plugin_register( $self, 'SERVER', qw(public) );
     return 1;
 }

 # This is method is mandatory but we don't actually have anything to do.
 sub PCI_unregister {
     return 1;
 }
 sub S_public {
     my ($self, $irc) = splice @_, 0, 2;

     # Parameters are passed as scalar-refs including arrayrefs.
     my $nick    = ( split /!/, ${ $_[0] } )[0];
     my $channel = ${ $_[1] }->[0];
     my $msg     = ${ $_[2] };
	 $msg = &Trice::clean($msg);

	 if($msg =~ /^\!((u|user) ([a-zA-Z0-9]+)|user|u)$/i){
		 my ($user, $output, $uploaded, $downloaded, $ratio, $result, $result2, $sql_rows, $Snatched, $Seeding, $Leeching, $UserID, $donor, $banned, $warned, $onirc, $title, $extra_info);
		 
		 #get the users info
		 my($user_id, $username, $class, $is_admin) = &user::auth_user(${ $_[0] });
		 
		     
		 # Get the user permissions from DB
		 my $perms;
		 if($cfg->param("use_oper")){
			($perms) = user::check_permissions($username);
			$perms = $perms->{Level};
		 } else {
			 $perms = "200";
		 }
		 if($perms >= 100 || $is_admin == 1 || uc($channel) eq uc($cfg->param("irc_chan_staff"))) {
			 my $extra_columns = '';
			 my $allowed_user_classes = join ('|', $cfg->param("user_cmd_access"));
			 my $match =  "^\!(u|user)";
			if ($msg =~ m/$match (\w+)/i) {
				my $user_search = $2;
				# If allowed type class found grant access to !user nick
				if ($class =~ m/($allowed_user_classes)/i || uc($channel) eq uc($cfg->param("irc_chan_staff")) || $username eq $user_search) {
					$user = $user_search;
				} else {
					 $user = $nick;
					 $irc->yield(privmsg => $channel => "Sorry, you are not allowed to do that.");
					 return 1;
				}
			} else {  
				$user = $nick;
			}
			# If we are on Staff channel, show some extra info
			if (uc($channel) eq uc($cfg->param("irc_chan_staff"))) {
	    
				# Prepare MySQL query
				my $query = "SELECT um.Username, 
									um.ID, 
									um.Title, 
									um.Uploaded,
									um.Downloaded,
									um.Enabled, 
									um.PermissionID, 
									ui.Donor, 
									ui.Warned, 
									p.Name, 
									um.Email, 
									um.IP, 
									DATE_FORMAT(ui.JoinDate, '%Y-%m-%d') AS JoinDate
									FROM users_main AS um 
									JOIN users_info AS ui ON ui.UserID=um.ID 
									JOIN permissions AS p ON p.ID=um.PermissionID 
									WHERE um.Username='$user'";
	
				# Execute MySQL query and store it in hash
				my $sql = $db->prepare($query); $sql->execute();
	
				$result = $sql->fetchrow_hashref();

				if (defined $result->{ID} && $result->{ID} ne '') { $UserID = $result->{ID} } else { 
					$irc->yield(privmsg => $channel => "Sorry, can't find user: $user"); 
					return PCI_EAT_ALL; 
				}

				$sql_rows           = $sql->rows; # Need this bit later specifically from this query
				$result->{Paranoia} = '0';        # We set this to skip users paranoia settings in staff channel

				# Some extra queries in Staff
				$query = "SELECT COUNT(x.uid) AS Snatched FROM xbt_snatched AS x INNER JOIN torrents AS t ON t.ID=x.fid WHERE x.uid='$UserID'";
				$sql = $db->prepare($query); $sql->execute();
				$result2 = $sql->fetchrow_hashref();

				$Snatched = $result2->{Snatched}; $Snatched = '0' if ($Snatched eq '');

				# Some extra queries in Staff
				$query = "SELECT COUNT(x.uid) AS Leeching FROM xbt_files_users AS x INNER JOIN torrents AS t ON t.ID=x.fid WHERE x.uid='$UserID' AND x.remaining>0";
				$sql = $db->prepare($query); $sql->execute();
				$result2 = $sql->fetchrow_hashref();
				$Leeching = $result2->{Leeching}; $Leeching = '0' if ($Leeching eq '');

				# Some extra queries in Staff
				$query = "SELECT COUNT(x.uid) AS Seeding FROM xbt_files_users AS x INNER JOIN torrents AS t ON t.ID=x.fid WHERE x.uid='$UserID' AND x.remaining=0";
				$sql = $db->prepare($query); $sql->execute();
				$result2 = $sql->fetchrow_hashref();
				$Seeding = $result2->{Seeding}; $Seeding = '0' if ($Seeding eq '');

			} else { # not on staff channel so show limited info
	   	
				# Prepare MySQL quory
				my $query = "SELECT um.Username, 
									um.ID, 
									um.Title, 
									um.Uploaded, 
									um.Downloaded,
									um.Enabled,
									um.Paranoia,
									um.PermissionID,  
									ui.Donor, 
									ui.Warned,  
									p.Name
									FROM users_main AS um 
									JOIN users_info AS ui ON ui.UserID=um.ID 
									JOIN permissions AS p ON p.ID=um.PermissionID 
									WHERE um.Username='$user'";
	
				# Execute MySQL query and store it in hash
				my $sql = $db->prepare($query); $sql->execute();
				$result = $sql->fetchrow_hashref();
				$sql_rows = $sql->rows; # need this bit later

				if (defined $result->{ID} && $result->{ID} ne '') { $UserID = $result->{ID} } else { 
					$irc->yield(privmsg => $channel => "Sorry, can't find user: $user"); 
					return PCI_EAT_ALL; 
				}
			}
			# Let's print what we got
			if ($sql_rows > 0) {
				# Show upload stats if paranoia settings allow it
				if ($result->{Paranoia} < 4) {
					if ($result->{Uploaded} != 0) { $uploaded = Trice::convert_bytes($result->{Uploaded}, '2') } else { $uploaded = 0 };
				} else { $uploaded = 'hidden' }
			
				# Show download stats if paranoia settings allow it
				if ($result->{Paranoia} < 4) {
					if ($result->{Downloaded} != 0) { $downloaded = Trice::convert_bytes($result->{Downloaded}, '2') } else { $downloaded = 0 };
				} else { $downloaded = 'hidden' }
				
				if ($result->{Paranoia} < 4) {
					if($result->{Uploaded} != 0 and $result->{Downloaded} != 0){
						$ratio = $result->{Uploaded} / $result->{Downloaded};
						$ratio = sprintf "%.2f", $ratio;
					} else {
						$ratio = "0.00";
					}
				} else { $ratio = 'hidden' }
			
				if ($result->{Donor} == 1) { $donor = "\0033Donor:\0035 <3"; } else { $donor = "\0033Donor:\0037 No" };
				if ($result->{Enabled} == 1) { $banned = "\0033Banned:\0037 No"; } elsif($result->{Enabled} == 2) { $banned = "\0033Banned: \0035Yes" } else { $banned = "\0033Banned: \0035UC" };
				if ($result->{Warned} eq '0000-00-00 00:00:00') { $warned = "\0033Warned:\0037 No"; } else { $warned = "\0033Warned:\0035 $result->{Warned}" };
				if ($result->{Title} eq '') { $title = ""; } else { $title = " - " .$result->{Title}; $title =~ s/â.¥/<3/g; $title =~ s///g; };
				
				# Here's the final output
				$output = "\00310,01[\0037 ".$result->{Username}.$title." \00310] :: [\0033 ".$result->{Name}." \00310] :: [\0033 Uploaded:\0037 ".$uploaded." \00310|\0033 Downloaded:\0037 ".$downloaded." \00310|\0033 Ratio:\0037 ".$ratio." \00310] :: [\00314 http://".$cfg->param("site_url")."/user.php?id=".$result->{ID}." \00310]\017";
				$irc->yield(privmsg => $channel => $output);

				# Build extra line for #staff
				if (uc($channel) eq uc($cfg->param('irc_chan_staff'))) {
					# Here's the extra info for staff
					$extra_info = "\00310,01[\0033 Snatched:\0037 " . $Snatched . " \00310|\0033 Seeding:\0037 " . $Seeding . " \00310|\0033 Leeching:\0037 " . $Leeching . " \00310] :: [ " . $donor . " \00310| " . $banned . " \00310| " . $warned . " \00310] :: [\0033 Joined:\0037 " . $result->{JoinDate} . " \00310|\0033 Email:\0037 " . $result->{Email} . " \00310|\0033 IP:\0037 " . $result->{IP} . " \00310]"; 
					$irc->yield(privmsg => $channel => $extra_info);
				}   
			} else {
				$irc->yield(privmsg => $channel => "Sorry, can't find user: $user");
			}
		} else {
			$irc->yield(privmsg => $channel => "You don't have sufficient permissions to run this command or maybe you haven't authenticated with the Bot?");
		}
		return PCI_EAT_ALL;
	 }
	 
	 return PCI_EAT_NONE;
 }

 sub auth_user {
	 my($host) = @_;
	 #Uses regex on the users host
	 if($host =~ /(\d+)\@(\S+)\.(\S+)\.$url/i){
		 my($user_id, $username, $class) = ($1, $2, $3);
		 if($user_id){
			 my $sql = $db->prepare("SELECT um.Username, p.Name FROM users_main AS um LEFT JOIN permissions AS p ON p.ID=um.PermissionID WHERE um.ID = ?");
			 $sql->execute($user_id);
			 ($username, $class) = $sql->fetchrow_array();
		 }
		 #Joins all admin classes
		 my $admin_users = join ('|', $cfg->param("site_admins"));
		 my $is_admin = '0';
		 if($class =~ m/($admin_users)/i) {
			$is_admin = 1;
		 }
		 return ($user_id, $username, $class, $is_admin);
	 } else {
	         my $user    = ( split /!/, $host)[0];
			 my $sql = $db->prepare("SELECT um.ID, um.Username, p.Name FROM users_main AS um LEFT JOIN permissions AS p ON p.ID=um.PermissionID WHERE um.Username = ?");
			 $sql->execute($user);
			 my ($user_id, $username, $class) = $sql->fetchrow_array();
			 #Joins all admin classes
			 my $admin_users = join ('|', $cfg->param("site_admins"));
			 my $is_admin = '0';
			 if($class =~ m/($admin_users)/i) {
				$is_admin = 1;
			 }
			 if($user_id){
				return ($user_id, $username, $class, $is_admin);
			 } else {
				return 0;
			}
	 }
 }
 
sub check_permissions {
    my ($user) = @_;   
    my $query = "SELECT um.Username, 
                        um.ID, 
                        um.Enabled, 
                        um.PermissionID, 
                        p.Level 
                   FROM users_main AS um 
                   JOIN permissions AS p ON p.ID=um.PermissionID 
                  WHERE um.Username='$user'";
    my $sql = $db->prepare($query);
    $sql->execute();
    
    my $result = $sql->fetchrow_hashref();

    # Didn't find the user level so set to '0'
    if ($sql->rows == 0) {
		$result->{Level} = '0';
    }

    return $result;
}
 
 1;
