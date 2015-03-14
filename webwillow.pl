#!/usr/bin/perl


##################################################################################################################
# 
# File         : webwillow.pl
# Description  : crawls/spiders web pages and summarises content according to patterns you define
# Original Date: ~1997
# Author       : simran@dn.gs
#
##################################################################################################################


require 5.004;

$|=1;

# use HTML::Parse;

require 5.002;
use Socket;
use Carp;
use FileHandle;

$|=1;


###### read in args etc... #############################################################################
#
#
#

($cmd = $0) =~ s:(.*/)::g;
($startdir = $0) =~ s/$cmd$//g;

# defined defaults that can be overwritten by command line switches or in the config file... 
$configfile = "${startdir}webwillow.conf";
$timeout = 30 if (! $timeout);
$maxdepth = 10 if (! $maxdepth);
###

while (@ARGV) { 
  $arg = "$ARGV[0]";
  $nextarg = "$ARGV[1]";
  if ($arg =~ /^-c$/i) {
    $configfile = "$nextarg";
    die "Valid configfile not defined after -c switch : $!" if (! -f "$configfile");
    shift(@ARGV);
    shift(@ARGV);
    next;
  }
  elsif ($arg =~ /^-nologs$/i) {
    $arg_nologs = 1;
    shift(@ARGV);
    next;
  }
  elsif ($arg =~ /^-about$/i) {
    shift(@ARGV);
    &about();
  }
  else { 
    print "\n\nArgument $arg not understood.\n";
    &usage();
  }
}

#
#
#
#########################################################################################################


#### main program #####################################################################################
#
#
#

$SIG{'INT'} = sub { $start_end = 1; &printout(); };

$webwillow_starttime = localtime;

# set some default values in case they are not specified in the config file... 
$numwords = 50;

&readconf();

# override some values from the config file if they were respecified on the command line... 

$logfile = "" if ($arg_nologs);

&startgetinfo();

&printout();

#
#
#
#########################################################################################################


########################################################################################################
# readconf: Reads config file
#
#  global vars read: 
#	 # $configfile 
# 
#  global vars possibly created/modified: 
#        # $template		 - template file
#        # $outfile		 - output html file
#        # %settings
#	 #  $settings{"$name"}{"host"} = $host
#	 #  $settings{"$name"}{"base"} = $base
#	 #  $settings{"$name"}{"regex"} = $regex
#	 #  $settings{"$name"}{"exclude"} = $exclude
#	 #  $settings{"$name"}{"port"} = $port 
#

sub readconf {

  my (@conffile, $tag, $conffile_linenum, $rest, $pattern, $name, $host, $port);

  open(CONFFILE, "$configfile") || &usage("Could not open $configfile : $!");
  @conffile = <CONFFILE>;
  close(CONFFILE);
 
  $conffile_linenum = 1; 
  while(@conffile) {
    $confline = shift(@conffile);
    chomp($confline);
    if ($confline =~ /^[\s\t]*#/i) { $conffile_linenum++; next; }    # ignore comment lines 
    if ($confline =~ /^[\s\t]*$/i) { $conffile_linenum++; next; }    # ignore blank lines 

    $confline =~ s/#.*$//g; # remote comments bits after the '#' symbol in conffile 

    $conffile_linenum++;

    # handle 'template' line 
    if ($confline =~ /^template:/i) {
      ($tag, $template) = split(/:/,"$confline", 2);
      $template = strip("$template");
    }
    # hanndle 'outfile' line
    elsif ($confline =~ /^outfile:/i) {
      ($tag, $outfile) = split(/:/,"$confline", 2);
      $outfile = strip("$outfile");
    }
    # hanndle 'numwords' line
    elsif ($confline =~ /^numwords:/i) {
      ($tag, $numwords) = split(/:/,"$confline", 2);
      $numwords = strip("$numwords");
      die "numwords must be greater than 0" if (! $numwords || $numwords !~ /\d+/);
    }
    # hanndle 'maxdepth' line
    elsif ($confline =~ /^maxdepth:/i) {
      ($tag, $maxdepth) = split(/:/,"$confline", 2);
      $maxdepth = strip("$maxdepth");
      die "Maxdepth numst be a numeric number at $configfile line $conffile_linenum\n" if ($maxdepth !~ /\d+/);
    }
    # hanndle 'timeout' line
    elsif ($confline =~ /^timeout:/i) {
      ($tag, $timeout) = split(/:/,"$confline", 2);
      $timeout = strip("$timeout");
    }
    # hanndle 'logfile' line
    elsif ($confline =~ /^logfile:/i) {
      ($tag, $logfile) = split(/:/,"$confline", 2);
      $logfile = strip("$logfile");
    }
    # hanndle 'set' line
    elsif ($confline =~ /^set /i) {
      ($tag, $setname, $setvalue) = split(/\s+/,"$confline", 3);
      $setname = strip("$setname");
      if ($setname !~ /^WILLOW_/) {
	print STDERR "Any variable that you are custom setting must begin with 'willow_'\n";
	print STDERR "eg. set willow_mytime time\n";
	exit(1);
      }
      $setvalue = strip("$setvalue");
      $setvalue = eval "$setvalue";
      chomp($setvalue);
      $custom{"$setname"} = "$setvalue";
      $$$setname = "$setvalue"; # this command does not work in perl releases prior to 5.004 !
    }
    # handle 'proxy' line
    elsif ($confline =~ /^proxy:/i) {
      ($tag,$rest) = split(/:/, "$confline", 2);
      ($host, $port) = split(/:/, "$rest", 2);
      die "Port number must be specified with proxy host" if (! $port);
      die "Port must be numeric at config file line $conffile_linenum\n" if ($port !~ /^\d+$/);
      # $host = strip("$host");
      # $port = strip("$port");
      $proxy_host = "$host";
      $proxy_port = "$port";
    }
    # handle 'name' line
    elsif ($confline =~ /^name:/i) {
      ($tag,$name) = split(/:/, "$confline", 2);
      $name = strip("$name");
      die "Name field cannot be empty at $configfile line $conffile_linenum\n" if (! "$name");
      $settings{"$name"}{"name"} = 1;

      while($confline !~ /^[\s\t]*$/) {
	$conffile_linenum++;
	$confline = shift(@conffile);
	next if ($confline =~ /^[\s\t]*$/);
	next if ($confline =~ /^[\s\t]#/);
	($tag, $rest) = split(/:/, "$confline", 2);
	$tag = strip("$tag");
	$rest = strip("$rest");
        foreach $setname (keys %custom) {
 	  $rest =~ s:\$\$$setname:$custom{"$setname"}:g;
        }
	die "Field cannot be empty for tag $tag in $configfile at $conffile_linenum\n" if (! "$rest");
	# handle 'host' line 
	if ($tag =~ /^host$/i) {
	  ($host, $port) = split(/:/, "$rest", 2);
	  $port = 80 if (! $port);
	  die "Port must be numeric at config file line $conffile_linenum\n" if ($port !~ /^\d+$/);
	  $settings{"$name"}{"host"} = "$host";
	  $settings{"$name"}{"port"} = "$port";
	}
	elsif ($tag =~ /^base$/i) {
	  $settings{"$name"}{"base"} = "$rest";
	}
	elsif ($tag =~ /^regex$/i) {
          $rest =~ s!/!\\/!g; # put in escapes for all the '/'s
	  $settings{"$name"}{"regex"} = "$rest";
	}
	elsif ($tag =~ /^exclude$/i) {
          $rest =~ s!/!\\/!g; # put in escapes for all the '/'s
	  $settings{"$name"}{"exclude"} = "$rest";
	}
	else {
	  next if ($confline =~ /^[\s\t]*#/);
	  die "Tag $tag not defined under name - config file line $conffile_linenum:"; 
	}
      }
      die "Host not defined for name $name\n" if (! $settings{"$name"}{"host"});
      die "Base not defined for name $name\n" if (! $settings{"$name"}{"base"});
      die "Regex not defined for name $name\n" if (! $settings{"$name"}{"regex"});

      $name = "";
    }
    else {
      print STDERR  "Did not understand \"$confline\" - config file line $conffile_linenum \n"; 
      print STDERR  "Did it need to be predeeded by a 'name' tag ?\n";
      exit(1);
    } # end if/elsif/else
  } # end while

  # check for essential variables... and if not defined... exit... 

} # end sub
#
#
#
##########################################################################################################


##########################################################################################################
# $str strip($string): return $string stripped of leading and trailing white spaces... 
#
#
sub strip {
  $_ = "@_";
  $_ =~ s/(^[\s\t]*)|([\s\t]*$)//g;
  return "$_";
}
#
#
#
###########################################################################################################


###########################################################################################################
# setupWebServer: sets up connection to remote server 
# 
# FileHandle Created : 'WebServer'
#
sub setupWebServer { 
  my ($remotehost, $remoteport) = @_;
  my $proto = getprotobyname('tcp');
  my ($remote_iaddr, $remote_paddr);


  $remote_iaddr = inet_aton($remotehost);
  $remote_paddr = sockaddr_in($remoteport,$remote_iaddr);
  socket(WebServer, PF_INET, SOCK_STREAM, $proto) or die "socket: $!";
  if (! connect(WebServer, $remote_paddr)) {
    $alarmcode = 1;
    $alarm_host = $remotehost;
    $alarm_port = $remoteport;
    &alarmcall();
  }
}
#
#
#
##########################################################################################################


###########################################################################################################
# usage: prints usage... 
#
#
sub usage {
  print "\n\n@_\n";
  print << "EOUSAGE"; 

Usage: $cmd [options]

   # no options - assumes webwillow.conf file is in the same directory as '$cmd'
       
   -c file      # file to use as config file... 
   -nologs	# logs will not be kept even if there is a logfile specified in the config file... 
   -about	# About this program.


EOUSAGE
  exit(0);
}
#
#
#
########################################################################################################

########################################################################################################
# sub alarmcall: # the subroutine that is called when requests take 
#                # assumes the variables $name is set! 
#
sub alarmcall {
  my $signame = shift;
  my $realreason;

  $host = $settings{"$name"}{"host"};
  $port = $settings{"$name"}{"port"};

  if ($proxy_host && $proxy_port) {
    $host = "$proxy_host";
    $port = "$proxy_port";
  }

  my $reason0 = "The reason for the alarm is unknown";
  my $reason1 = "The remote host $host port $port could not be contacted via the 'connect' function in perl";
  my $reason2 = "The remote host $host had not finished responding within $timeout seconds";

  $realreason = "$reason0" if ($alarmcode == 0);
  $realreason = "$reason1" if ($alarmcode == 1);
  $realreason = "$reason2" if ($alarmcode == 2);

  print STDERR "$realreason\n";

  # close(WebServer);
  # exit(1);
}
#
#
#
#########################################################################################################

##############################################################################################################
#
# sub getURL($host, $port, $uri) : Gets the URL and returns the contents... 
#                                  Including the header info... 
#
sub getURL {
  my ($host, $port, $uri) = @_;
  my @tmp;
  my $content;
  my @tosend;

  if ($proxy_host && $proxy_port) {
    setupWebServer("$proxy_host", "$proxy_port");
    $tosend = <<"EOTOSEND";
GET http://${host}:${port}${uri} HTTP/1.0
User-Agent: I'm a little robot

EOTOSEND
  }
  else {
    setupWebServer("$host", "$port");
    $tosend = <<"EOTOSEND";
GET $uri HTTP/1.0
User-Agent: I'm a little robot

EOTOSEND
  }

  $tosend .= "\n";

  send(WebServer, "$tosend", 0) || warn "send: $!";
  $SIG{ALRM} = \&alarmcall;
  $alarm_host = "$host";
  $alarm_port = "$port";
  $alarmcode = 2;
  alarm($timeout);
  @tmp = <WebServer>;
  alarm 0;
  $alarmcode = 0;
  $content = join(' ',@tmp);
  close(WebServer);
  return "$content";
}
#
#
#
############################################################################################################

############################################################################################################
#
# sub getinfo("$name", "$uri") - goes through the uri's that can match url's patterns and creates 
#
#			 $data{"$name"}{"$uri"}{"title"} = $title
#			 $data{"$name"}{"$uri"}{"firstfew"} = $firstfew
#       
#   Global variables used: %settings
#			   %done{"$url"};
#
sub getinfo {
  my ($name, $uri) = @_;
  my ($host, $port, $regex, $base, $content, $url, $gotcontent, $parsed_file, $uridir);
  my ($inheader, $line, $exclude, $depth);
  my (@uris);

  @uris = (); 

  $depth = ($uri =~ tr/\//\//) - 1;
  return "" if ($depth > $maxdepth);
  
  $gotcontent = 0;

  $host = $settings{"$name"}{"host"};
  $base = $settings{"$name"}{"base"};
  $port = $settings{"$name"}{"port"};
  $regex = $settings{"$name"}{"regex"};
  $exclude = $settings{"$name"}{"exclude"};

  $uridir = "$uri";
  if ($uridir !~ /\//) { # if uridir does not end with a '/' make it = base
    $uridir = "$base";
  }
  else {
    $uridir =~ /(.*)\/.*?/g; # else get everything before the last '/' and
    			    # that must be the directory...
    $uridir = "$1";
  }


  # make sure we don't go in recursive loops...
  $url = "${host}:${port}${uri}";
  $url = strip("$url");
  if ($done{"$url"}) {
    return;
  }
  else {
    $done{"$url"} = 1; # code '1' = examine only! 
  }

  print "Trying out URL $url\n";

  if (! $exclude) {
    # make sure that if there were not excludes defined $uri cannot match it! 
    $exclude = "this_is_not_going_to_match_$uri";
  }


  if ($uri =~ /^$base/ && $uri =~ /$regex/i && $uri !~ /$exclude/i) {

    $done{"$url"} = 2; # code '2' = examine and match

    # print STDERR "        Matched URL $url\n";
    
    # real recording here... ie. we have a match according to what
    # is specified in the config file... so record appropriate fields
    # in %data

    $content = getURL("$host", "$port", "$uri");
    $gotcontent = 1;

    ($title = $content) =~ s/\n/  /g;
    $title =~ /.*?<title>(.*?)<\/title>.*?/ig;
    $title = "$1";
    $title = "$url" if (! $title);

    $firstfew = &getfirstfew("$content");

    $data{"$name"}{"$uri"}{"title"} = "$title";
    $data{"$name"}{"$uri"}{"firstfew"} = "$firstfew";
  }

  if ($uri =~ /^$base/ ) {
  
    # if the uri is within our base directory, it can contain possible
    # other uri's we might want... so look for links within it and 
    # record them for processing... 

    $content = getURL("$host", "$port", "$uri") if (! $gotcontent);
    $gotcontent = 1;

    # $parsed_file = HTML::Parse::parse_html("$content");
    # foreach $_ (@{$parsed_file->extract_links(qw(a))}) { 

    foreach $uri (&getlinks("$content")) {
      # $uri = $_->[0];
      next if ($uri =~ /^http/i); # ignore if the url is absolute ... it is probably
      				  # pointing to another server...!!! 
      push(@uris, "$uri");
    }

    foreach $uri (@uris) {
      $uri = &fixuri("$name", "$uridir", "$uri");
      next if (! "$uri");
      &getinfo("$name", "$uri");
    }


  }
}
#
#
#
############################################################################################################


############################################################################################################
#
# fixuri("$name", "$uri") : returns an absolute path URI
#
sub fixuri { 
  my ($name, $uridir, $uri) = @_;

  if ($uri =~ /^\//) {     # if uri started with '/' it is absolute anyway so just return that... !!! 
    return "$uri";
  }
	
  
  $uridir =~ s:":/:g; 
  $uridir =~ s:/$::g;

  while ($uri =~ /^\.\.\//) {
    # while the uri is something like ../../images/blah.gif 
    # for each ../ go back one level in urldir and remove ../
    # this is because we only request for 'absolute uri's 
    # and uri's like /~simran/art/forrest/../../images/blah.gif is not
    # valid because of security reasons! 
    $uri =~ s/^\.\.\///g;
    $uridir =~ /(.*)\/.*/g;
    $uridir = "$1";
  }

  $uri = "${uridir}/${uri}";

  $uri =~ s:":/:g; 
  $uri =~ s:\./::g; # replace any "./" for cases like "./contents.html"
  $uri =~ s://*:/:g; # replace any '//' double or more slashes that might have creeped in! 

  $uri =~ "/$uri" if ($uri !~ /^\//); # put a '/' in front if there isn't already! 

  return "$uri";

}
#
#
#
############################################################################################################

############################################################################################################
#
# printout: takes no arguments... but assumes that TMPL and OUTFILE and defined
#           and opened... 
#
sub printout {

  # work out globally defined variables for template here! 
  $TIME = localtime;

  $inwillow = 0;

  while ($line = <TMPL>) {
    $template_line++;
    chomp($line);
    next if ($line =~ /^#/);
    if ($line =~ /<willow name=(.*)>(.*?)$/) {
      $name = "$1";
      $rest = "$2";
      die "<willow> line for $name is not by itself... line $template_line" if ($rest !~ /^\s*$/);
      $inwillow = 1;
    }
    elsif ($line =~ /<\/willow>(.*?)$/) {
      $rest = "$1";
      die "</willow> line for $name is not by itself... line $template_line" if ($rest !~ /^\s*$/);
      $inwillow = 0;

      $orig_willow_template = $willow_template;
      foreach $uri (keys %{$data{"$name"}}) {
        # work out variables that are valid within the <willow> and </willow> tags here! 
	$URI = "$uri";
        $host = $settings{"$name"}{"host"};
        $port = $settings{"$name"}{"port"};
	$URL = "http://${host}:${port}${URI}";
        $TITLE = $data{"$name"}{"$uri"}{"title"};
        $FIRST_FEW_WORDS = $data{"$name"}{"$uri"}{"firstfew"};
	$willow_template =~ s:\$\$TITLE:$TITLE:g;
	$willow_template =~ s:\$\$URL:$URL:g;
	$willow_template =~ s:\$\$FIRST_FEW_WORDS:$FIRST_FEW_WORDS:g;
        print OUTFILE "$willow_template\n";
	$willow_template = $orig_willow_template;
      }
      $willow_template = "";
    }
    elsif ($inwillow) {
      $willow_template .= "$line\n";
    }
    else {
      $line =~ s:\$\$TIME:$TIME:g;

      foreach $setname (keys %custom) {
 	$line =~ s:\$\$$setname:$custom{"$setname"}:g;
      }

      print OUTFILE "$line\n";
    }

  }

  # handle output to log file... 
  if ($logfile) {
    $matched = $examined = $total = 0;
    $timenow = localtime;
    print LOGFILE "\n\n\n-------------------------------------------------------------\n";
    print LOGFILE "Recording log at $timenow\n";
    foreach $url (keys %done) {
      if ($done{"$url"} == 1) {
	print LOGFILE "Examined but no match for URL : $url\n";
	$examined++;
      }
      if ($done{"$url"} == 2) {
	print LOGFILE "Examined and match for URL : $url\n";
	$matched++;
      }
    }
    $total = $examined + $matched;
    print LOGFILE "Examined: $examined     Matched: $matched      Total: $total\n";
    print LOGFILE "WebWillow started at $webwillow_starttime and finished at $timenow\n";
  }


  if ($start_end) {
    print STDERR "Interrupt signal caught ... quitting\n";
    exit(0);
  }


}
#
#
# 
############################################################################################################

############################################################################################################
#
# startgetinfo: 
# put some stuff that could go in 'main' section here... only so that the 'main' section
# looks neater... :)
#
sub startgetinfo {

  open(OUTFILE, "> $outfile") || die "Could not open $outfile for writing : $!";
  open(TMPL, "$template") || die "Could not open $template for reading : $!";

  if ($logfile) {
    open(LOGFILE, ">> $logfile") || die "Could not open logfile $logfile for writing : $!";
  }

  OUTFILE->autoflush();

  foreach $name (keys %settings) {
      $base = $settings{"$name"}{"base"};
        &getinfo("$name", "$base");
  }

}
#
#
#
############################################################################################################

############################################################################################################
#
# getfirstfew ($content) : returns the first few words in $content... ignores headers and a few
#                          other things... 
#
sub getfirstfew {
    
  my $content = "@_";
  my $inheader = 1;
  my ($firstfewwords,$inheader,$word);

  # get rid of HTTP header... 
  foreach $line (split(/\n/, $content)) {
    $inheader = 0 if ($line =~ /^\s*$/);
    next if ($inheader);
    $firstfew .= "$line";
  }

  # only look within 'body' and '/body' tags... 
  $firstfew =~ /<body.*?>(.*)<\/body>/mi;
  $firstfew = "$1";

  $firstfew =~ s/(<.*?>)//g;

  $firstfew =~ s/\n/<br>\n/g;

  $firstfewnum = $numwords;

  foreach $word (split(/\s+/, "$firstfew")) {
    last if ($firstfewnum < 0);
    $firstfewnum--;
    $firstfewwords .= " $word";
  }

  return "$firstfewwords";
}

#
#
#
############################################################################################################

############################################################################################################
#
# getlinks($content) : returns all the "<a href=" links in the document
#
#
sub getlinks {
  my $content = "@_";
  my @links, $link;

  @links = ();

  $content =~ s/\n/ /g;
  $content =~ s/\s+/ /g;

  while ($content =~ /<a\s+href=/i) {
    $content =~ /.*?<a\s+href=(.*)[ >].*?<\/a>/im;
    $link = "$1";
    $link =~ s/>.*//g;
    $link =~ s/"//g;
    push(@links, "$link");
    $content =~ s/<a\s+href=//i;
  }

  return @links;
}
#
#
#
############################################################################################################
 
############################################################################################################
#
#
#
sub about {
  print <<"EOABOUT";

  WebWillow 
  ---------

  Written to collect info that is interesting and chaning
  on a routine basis on various pages and sites, and form
  one page with summarised info so you don't have to go to
  lots of pages and check them out on a routine basis! 

  Please mail comments/suggestions to simran\@cse.unsw.edu.au

EOABOUT
  exit(0);
}
#
#
#
############################################################################################################


