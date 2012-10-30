About
=====

This is a bot for Gazelle websites that want to secure their IRC channels. It allows users to authenticate using their credentials on-site and thus be authorised for official channels on IRC.

Features
=========

Trice is fast, secure, reliable and stable. It is written in perl and utilizes the POE::Component::IRC framework. It has a plugin system which allows admins to load/unload plugins on the fly without the need to restart the bot. It also has a logging system with error reporting.

Requriements
============

Trice uses perl with some perl modules.

Debian/Ubuntu
--------------

`apt-get install perl libpoe-component-irc-perl libpoe-component-pluggable-perl libwww-perl libconfig-simple-perl libmodule-refresh-perl libwww-mechanize-perl libnet-dns-perl libgeo-ip-perl libdate-pcalc-perl liblog-log4perl-perl libclass-unload-perl`

Download
---------

You can download an archive or checkout the latest stable revision from GIT.

Configuration
===========

The bot requires bot.cfg to be in its folder. It comes with an example configuration file bot.cfg.example which documents all the configuration options.

Required database schema
------------------------

*Table*: users_main
*Fields*: ID, Username, IRCKey, PassHash, Secret, PermissionID, onirc

*Table*: permissions
*Fields*: ID, Name

*Table*: irc_channels
*Fields*: ID, Channel, Level

Plugins
=======

Trice is extensible through a plugin system. Currently there are three official plugins available:

* User - A simple !user command to view user stats. 
* Enter - A plugin that secures your IRC channels.
* Announce - Allows your site to send messages to IRC.
* IRC Bonus - Marks a user as on irc when they join your channel.

Running
=======

The bot can be run very simply by the command `perl bot.pl`

ubuntu/debian init script: https://github.com/AzzABTN/TriceBot/wiki/INIT-Script

Commands
========

###Enter


/msg Trice ENTER <nick> <irckey> <#channel>
Only lets the user in if they have the correct Nick, IRCKey and have perms to join the channel.

###User


!user <user>
This command gives a simple line about user info eg: [ AzzA - Hello ] :: [ Sysop ] :: [ Uploaded: 507.73 MB | Downloaded: 3.94 GB | Ratio: 0.13 ] :: [ https://broadcasthe.net/user.php?id=1 ]
It gives extra info like IP and email, when used in the staff channel.

Support
========

If you need support you can use the forum here, the issue tracker or hit me up on IRC. You may join our IRC at irc://irc.omgwtfhax.net #Trice

Information
============

Trice was written by AzzA using the POE::Component::IRC module in perl.