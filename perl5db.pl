package DB;

# Debugger for Perl 5.001m; perl5db.pl patch level 0.92
# Enhanced by ilya@math.ohio-state.edu (Ilya Zakharevich)
# Latest version available: ftp://ftp.math.ohio-state.edu/pub/users/ilya/perl

# modified Perl debugger, to be run from Emacs in perldb-mode
# Ray Lischner (uunet!mntgfx!lisch) as of 5 Nov 1990
# Johan Vromans -- upgrade to 4.0 pl 10
# Ilya Zakharevich -- patches after 5.001 (and some before ;-)

$header = '$RCSfile: perl5db.pl,v $$Revision: 4.1 $$Date: 92/08/07 18:24:07 $ ';
#
# This file is automatically included if you do perl -d.
# It's probably not useful to include this yourself.
#
# Perl supplies the values for @line and %sub.  It effectively inserts
# a &DB'DB(<linenum>); in front of every place that can
# have a breakpoint.  It also inserts a do 'perldb.pl' before the first line.
#
# $Log:	perldb.pl,v $

#
# At start reads $rcfile that may set important options.  This file
# may define a subroutine &afterinit that will be executed after the
# debugger is initialized.
#
# After $rcfile is read reads environment variable PERLDB_OPTS and parses
# it as a rest of `O ...' line in debugger prompt.
#
# The options that can be specified only at startup:
# [To set in $rcfile, call &parse_options("optionName=new_value").]
#
# TTY  - the TTY to use for debugging i/o.
#
# noTTY - if set, goes in NonStop mode.  On interrupt if TTY is not set
# uses the value of noTTY or "/tmp/perldbtty$$" to find TTY using
# Term::Rendezvous.  Current variant is to have the name of TTY in this
# file.
#
# ReadLine - If false, dummy ReadLine is used, so you can debug
# ReadLine applications.
#
# NonStop - if true, no i/o is performed until interrupt.
#
# LineInfo - file or pipe to print line number info to.  If it is a
# pipe, a short "emacs like" message is used.
#
# Example $rcfile: (delete leading hashes!)
#
# &parse_options("NonStop=1 LineInfo=db.out");
# sub afterinit { $trace = 1; }
#
# The script will run without human intervention, putting trace
# information into db.out.  (If you interrupt it, you would better
# reset LineInfo to something "interactive"!)
#


local($^W) = 0;

$OUT = \*STDERR;	# For errors before DB::OUT has been opened
$trace = $signal = $single = 0;	# uninitialized warning suppression

@hist = ('?');
$SIG{INT} = "DB::catch";
$deep = 100;		# warning if stack gets this deep
$window = 10;
$preview = 3;
$sub = '';

$db_stop = 0;			# Compiler warning
$db_stop = 1 << 30;
$level = 0;			# Level of recursive debugging
$sublevels = 0;			# Levels of subroutines until break
$#ARGS = $#ARGS;		# Avoid a warning

@stack = (0);

$option{PrintRet} = 1;
@options = qw(hashDepth arrayDepth DumpDBFiles dumpPackages compactDump
	      veryCompact quote HighBit undefPrint globPrint PrintRet TTY noTTY
	      ReadLine NonStop LineInfo recallCommand shellBang pager);
%optionAction = (
		 hashDepth	=> \&dumpvar::hashDepth,
		 arrayDepth	=> \&dumpvar::arrayDepth,
		 DumpDBFiles	=> \&dumpvar::dumpDBFiles,
		 dumpPackages	=> \&dumpvar::dumpPackages,
		 compactDump	=> \&dumpvar::compactDump,
		 veryCompact	=> \&dumpvar::veryCompact,
		 quote		=> \&dumpvar::quote,
		 HighBit	=> \&dumpvar::quoteHighBit,
		 undefPrint	=> \&dumpvar::printUndef,
		 globPrint	=> \&dumpvar::globPrint,
		 TTY		=> \&TTY,
		 noTTY		=> \&noTTY,
		 ReadLine	=> \&ReadLine,
		 NonStop	=> \&NonStop,
		 LineInfo	=> \&LineInfo,
		 recallCommand	=> \&recallCommand,
		 shellBang	=> \&shellBang,
		 pager		=> \&pager,
		);
%optionRequire = (
		  hashDepth	=> 'dumpvar.pl',
		  arrayDepth	=> 'dumpvar.pl',
		  DumpDBFiles	=> 'dumpvar.pl',
		  dumpPackages	=> 'dumpvar.pl',
		  compactDump	=> 'dumpvar.pl',
		  veryCompact	=> 'dumpvar.pl',
		  quote		=> 'dumpvar.pl',
		  HighBit	=> 'dumpvar.pl',
		  undefPrint	=> 'dumpvar.pl',
		  globPrint	=> 'dumpvar.pl',
		 );

# These guys may be defined in $ENV{PERL5DB} :
$rl = 1 unless defined $rl;
&pager(defined($ENV{PAGER}) ? $ENV{PAGER} : "|more") unless defined $pager;
&recallCommand("!") unless defined $prc;
&shellBang("!") unless defined $psh;

if (-e "/dev/tty") {
  $rcfile=".perldb";
} else {
  $rcfile="perldb.ini";
}

if (-f $rcfile) {
    do "./$rcfile";
} elsif (-f "$ENV{LOGDIR}/$rcfile") {
    do "$ENV{LOGDIR}/$rcfile";
} elsif (-f "$ENV{HOME}/$rcfile") {
    do "$ENV{HOME}/$rcfile";
}

if (defined $ENV{PERLDB_OPTS}) {
  parse_options($ENV{PERLDB_OPTS});
}

if ($notty) {
  $runnonstop = 1;
} else {
  # Is Perl being run from Emacs?
  $emacs = ((defined $main::ARGV[0]) and ($main::ARGV[0] eq '-emacs'));
  shift(@main::ARGV) if $emacs;

  #require Term::ReadLine;

  if (-e "/dev/tty") {
    $console = "/dev/tty";
  } elsif (-e "con") {
    $console = "con";
  } else {
    $console = "sys\$command";
  }

  # Around a bug:
  if (defined $ENV{OS2_SHELL}) { # In OS/2
    if ($DB::emacs) {
      $console = undef;
    } else {
      $console = "/dev/con";
    }
  }

  $console = $tty if defined $tty;

  open(IN,"+<$console") || open(IN,"<$console") || open(IN,"<&STDIN");
  # so open("|more") can read from STDOUT and so we don't dingle stdin
  $IN = \*IN;

  open(OUT,"+>$console") || open(OUT,">$console") || open(OUT,">&STDERR")
    || open(OUT,">&STDOUT");	# so we don't dongle stdout
  $OUT = \*OUT;
  select($OUT);
  $| = 1;			# for DB::OUT
  select(STDOUT);

  $LINEINFO = $OUT unless defined $LINEINFO;
  $lineinfo = $console unless defined $lineinfo;

  $| = 1;			# for real STDOUT

  $header =~ s/.Header: ([^,]+),v(\s+\S+\s+\S+).*$/$1$2/;
  unless ($runnonstop) {
    print $OUT "\nLoading DB routines from $header\n";
    print $OUT ("Emacs support ",
		$emacs ? "enabled" : "available",
		".\n");
    print $OUT "\nEnter h or `h h' for help.\n\n";
  }
}

@ARGS = @ARGV;
for (@args) {
    s/\'/\\\'/g;
    s/(.*)/'$1'/ unless /^-?[\d.]+$/;
}

if (defined &afterinit) {	# May be defined in $rcfile
  &afterinit();
}

############################################################ Subroutines

sub DB {
    if ($runnonstop) {		# Disable until signal
	for ($i=0; $i <= $#stack; ) {
	    $stack[$i++] &= ~1;
	}
	$single = $runnonstop = 0; # Once only
	return;
    }
    &save;
    if ($doret) {
	$doret = 0;
	if ($option{PrintRet}) {
	    print $OUT "$retctx context return from $lastsub:", 
	      ($retctx eq 'list') ? "\n" : " " ;
	    dumpit( ($retctx eq 'list') ? \@ret : $ret );
	}
    }
    ($package, $filename, $line) = caller;
    $usercontext = '($@, $!, $,, $/, $\, $^W) = @saved;' .
      "package $package;";	# this won't let them modify, alas
    local(*dbline) = "::_<$filename";
    $max = $#dbline;
    if (($stop,$action) = split(/\0/,$dbline{$line})) {
	if ($stop eq '1') {
	    $signal |= 1;
	} else {
	    $evalarg = "\$DB::signal |= do {$stop;}"; &eval;
	    $dbline{$line} =~ s/;9($|\0)/$1/;
	}
    }
    if ($single || $trace || $signal) {
	$term || &setterm;
	if ($emacs) {
	    print $LINEINFO "\032\032$filename:$line:0\n";
	} else {
	    $sub =~ s/\'/::/;
	    $prefix = $sub =~ /::/ ? "" : "${'package'}::";
	    $prefix .= "$sub($filename:";
	    if (length($prefix) > 30) {
		print $LINEINFO "$prefix$line):\n$line:\t",$dbline[$line];
		$prefix = "";
		$infix = ":\t";
	    } else {
		$infix = "):\t";
		print $LINEINFO "$prefix$line$infix",$dbline[$line];
	    }
	    for ($i = $line + 1; $i <= $max && $dbline[$i] == 0; ++$i) {
		last if $dbline[$i] =~ /^\s*(\}|\#|\n)/;
		print $LINEINFO "$prefix$i$infix",$dbline[$i];
	    }
	}
    }
    $evalarg = $action, &eval if $action;
    if ($single || $signal) {
	local $level = $level + 1;
	$evalarg = $pre, &eval if $pre;
	print $OUT $#stack . " levels deep in subroutine calls!\n"
	  if $single & 4;
	$start = $line;
      CMD:
	while (($term || &setterm),
	       defined ($cmd=$term->readline("  DB" . ('<' x $level) .
					     ($#hist+1) . ('>' x $level) .
					     " "))) {
	    {			# <-- Do we know what this brace is for?
		$single = 0;
		$signal = 0;
		$cmd =~ s/\\$// && do {
		    $cmd .= $term->readline("  cont: ");
		    redo CMD;
		};
		$cmd =~ /^q$/ && exit 0;
		$cmd =~ /^$/ && ($cmd = $laststep);
		push(@hist,$cmd) if length($cmd) > 1;
	      PIPE: {
		    ($i) = split(/\s+/,$cmd);
		    eval "\$cmd =~ $alias{$i}", print $OUT $@ if $alias{$i};
		    $cmd =~ /^h$/ && do {
			print $OUT $help;
			next CMD; };
		    $cmd =~ /^h\s+h$/ && do {
			print $OUT $summary;
			next CMD; };
		    $cmd =~ /^h\s+(\S)$/ && do {
			my $asked = "\Q$1";
			if ($help =~ /^($asked([\s\S]*?)\n)(\Z|[^\s$asked])/m) {
			    print $OUT $1;
			} else {
			    print $OUT "`$asked' is not a debugger command.\n";
			}
			next CMD; };
		    $cmd =~ /^t$/ && do {
			$trace = !$trace;
			print $OUT "Trace = ".($trace?"on":"off")."\n";
			next CMD; };
		    $cmd =~ /^S(\s+(!)?(.+))?$/ && do {
			$Srev = defined $2; $Spatt = $3; $Snocheck = ! defined $1;
			foreach $subname (sort(keys %sub)) {
			    if ($Snocheck or $Srev^($subname =~ /$Spatt/)) {
				print $OUT $subname,"\n";
			    }
			}
			next CMD; };
		    $cmd =~ s/^X\b/V $package/;
		    $cmd =~ /^V$/ && do {
			$cmd = "V $package"; };
		    $cmd =~ /^V\b\s*(\S+)\s*(.*)/ && do {
			local ($savout) = select($OUT);
			$packname = $1;
			@vars = split(' ',$2);
			do 'dumpvar.pl' unless defined &main::dumpvar;
			if (defined &main::dumpvar) {
			    &main::dumpvar($packname,@vars);
			} else {
			    print $OUT "dumpvar.pl not available.\n";
			}
			select ($savout);
			next CMD; };
		    $cmd =~ s/^x\b/ / && do { # So that will be evaled
			$onetimeDump = 1; };
		    $cmd =~ /^f\b\s*(.*)/ && do {
			$file = $1;
			if (!$file) {
			    print $OUT "The old f command is now the r command.\n";
			    print $OUT "The new f command switches filenames.\n";
			    next CMD;
			}
			if (!defined $main::{'_<' . $file}) {
			    if (($try) = grep(m#^_<.*$file#, keys %main::)) {{
					      $file = substr($try,2);
					      print "\n$file:\n";
					  }}
			}
			if (!defined $main::{'_<' . $file}) {
			    print $OUT "There's no code here matching $file.\n";
			    next CMD;
			} elsif ($file ne $filename) {
			    *dbline = "::_<$file";
			    $max = $#dbline;
			    $filename = $file;
			    $start = 1;
			    $cmd = "l";
			} };
		    $cmd =~ /^l\b\s*([':A-Za-z_][':\w]*)/ && do {
			$subname = $1;
			$subname =~ s/\'/::/;
			$subname = "main::".$subname unless $subname =~ /::/;
			$subname = "main".$subname if substr($subname,0,2) eq "::";
			($file,$subrange) = split(/:/,$sub{$subname});
			if ($file ne $filename) {
			    *dbline = "::_<$file";
			    $max = $#dbline;
			    $filename = $file;
			}
			if ($subrange) {
			    if (eval($subrange) < -$window) {
				$subrange =~ s/-.*/+/;
			    }
			    $cmd = "l $subrange";
			} else {
			    print $OUT "Subroutine $subname not found.\n";
			    next CMD;
			} };
		    $cmd =~ /^w\b\s*(\d*)$/ && do {
			$incr = $window - 1;
			$start = $1 if $1;
			$start -= $preview;
			$cmd = 'l ' . $start . '-' . ($start + $incr); };
		    $cmd =~ /^-$/ && do {
			$incr = $window - 1;
			$cmd = 'l ' . ($start-$window*2) . '+'; };
		    $cmd =~ /^l$/ && do {
			$incr = $window - 1;
			$cmd = 'l ' . $start . '-' . ($start + $incr); };
		    $cmd =~ /^l\b\s*(\d*)\+(\d*)$/ && do {
			$start = $1 if $1;
			$incr = $2;
			$incr = $window - 1 unless $incr;
			$cmd = 'l ' . $start . '-' . ($start + $incr); };
		    $cmd =~ /^l\b\s*(([\d\$\.]+)([-,]([\d\$\.]+))?)?/ && do {
			$end = (!$2) ? $max : ($4 ? $4 : $2);
			$end = $max if $end > $max;
			$i = $2;
			$i = $line if $i eq '.';
			$i = 1 if $i < 1;
			if ($emacs) {
			    print $OUT "\032\032$filename:$i:0\n";
			    $i = $end;
			} else {
			    for (; $i <= $end; $i++) {
				print $OUT "$i:\t", $dbline[$i];
				last if $signal;
			    }
			}
			$start = $i; # remember in case they want more
			$start = $max if $start > $max;
			next CMD; };
		    $cmd =~ /^D$/ && do {
			print $OUT "Deleting all breakpoints...\n";
			for ($i = 1; $i <= $max ; $i++) {
			    if (defined $dbline{$i}) {
				$dbline{$i} =~ s/^[^\0]+//;
				if ($dbline{$i} =~ s/^\0?$//) {
				    delete $dbline{$i};
				}
			    }
			}
			next CMD; };
		    $cmd =~ /^L$/ && do {
			for ($i = 1; $i <= $max; $i++) {
			    if (defined $dbline{$i}) {
				print $OUT "$i:\t", $dbline[$i];
				($stop,$action) = split(/\0/, $dbline{$i});
				print $OUT "  break if (", $stop, ")\n"
				  if $stop;
				print $OUT "  action:  ", $action, "\n"
				  if $action;
				last if $signal;
			    }
			}
			next CMD; };
		    $cmd =~ /^b\b\s*([':A-Za-z_][':\w]*)\s*(.*)/ && do {
			$subname = $1;
			$cond = $2 || '1';
			$subname =~ s/\'/::/;
			$subname = "${'package'}::" . $subname
			  unless $subname =~ /::/;
			$subname = "main".$subname if substr($subname,0,2) eq "::";
			# Filename below can contain ':'
			($file,$i) = ($sub{$subname} =~ /^(.*):(.*)$/);
			$i += 0;
			if ($i) {
			    $filename = $file;
			    *dbline = "::_<$filename";
			    $max = $#dbline;
			    ++$i while $dbline[$i] == 0 && $i < $max;
			    $dbline{$i} =~ s/^[^\0]*/$cond/;
			} else {
			    print $OUT "Subroutine $subname not found.\n";
			}
			next CMD; };
		    $cmd =~ /^b\b\s*(\d*)\s*(.*)/ && do {
			$i = ($1?$1:$line);
			$cond = $2 || '1';
			if ($dbline[$i] == 0) {
			    print $OUT "Line $i not breakable.\n";
			} else {
			    $dbline{$i} =~ s/^[^\0]*/$cond/;
			}
			next CMD; };
		    $cmd =~ /^d\b\s*(\d+)?/ && do {
			$i = ($1?$1:$line);
			$dbline{$i} =~ s/^[^\0]*//;
			delete $dbline{$i} if $dbline{$i} eq '';
			next CMD; };
		    $cmd =~ /^A$/ && do {
			for ($i = 1; $i <= $max ; $i++) {
			    if (defined $dbline{$i}) {
				$dbline{$i} =~ s/\0[^\0]*//;
				delete $dbline{$i} if $dbline{$i} eq '';
			    }
			}
			next CMD; };
		    $cmd =~ /^O\s*$/ && do {
			for (@options) {
			    &dump_option($_);
			}
			next CMD; };
		    $cmd =~ /^O\s*(\S.*)/ && do {
			parse_options($1);
			next CMD; };
		    $cmd =~ /^<\s*(.*)/ && do {
			$pre = action($1);
			next CMD; };
		    $cmd =~ /^>\s*(.*)/ && do {
			$post = action($1);
			next CMD; };
		    $cmd =~ /^a\b\s*(\d+)(\s+(.*))?/ && do {
			$i = $1; $j = $3;
			if ($dbline[$i] == 0) {
			    print $OUT "Line $i may not have an action.\n";
			} else {
			    $dbline{$i} =~ s/\0[^\0]*//;
			    $dbline{$i} .= "\0" . action($j);
			}
			next CMD; };
		    $cmd =~ /^n$/ && do {
			$single = 2;
			$laststep = $cmd;
			last CMD; };
		    $cmd =~ /^s$/ && do {
			$single = 1;
			$laststep = $cmd;
			last CMD; };
		    $cmd =~ /^c\b\s*(\d*)\s*$/ && do {
			$i = $1;
			if ($i) {
			    if ($dbline[$i] == 0) {
				print $OUT "Line $i not breakable.\n";
				next CMD;
			    }
			    $dbline{$i} =~ s/($|\0)/;9$1/; # add one-time-only b.p.
			}
			for ($i=0; $i <= $#stack; ) {
			    $stack[$i++] &= ~1;
			}
			last CMD; };
		    $cmd =~ /^r$/ && do {
			$stack[$#stack] |= 2;
			$doret = 1;
			last CMD; };
		    $cmd =~ /^T$/ && do {
			local($p,$f,$l,$s,$h,$a,@a,@sub);
			for ($i = 1; ($p,$f,$l,$s,$h,$w) = caller($i); $i++) {
			    @a = ();
			    for $arg (@args) {
				$_ = "$arg";
				s/'/\\'/g;
				s/([^\0]*)/'$1'/
				  unless /^(?: -?[\d.]+ | \*[\w:]* )$/x;
				s/([\200-\377])/sprintf("M-%c",ord($1)&0177)/eg;
				s/([\0-\37\177])/sprintf("^%c",ord($1)^64)/eg;
				push(@a, $_);
			    }
			    $w = $w ? '@ = ' : '$ = ';
			    $a = $h ? '(' . join(', ', @a) . ')' : '';
			    push(@sub, "$w$s$a from file $f line $l\n");
			    last if $signal;
			}
			for ($i=0; $i <= $#sub; $i++) {
			    last if $signal;
			    print $OUT $sub[$i];
			}
			next CMD; };
		    $cmd =~ /^\/(.*)$/ && do {
			$inpat = $1;
			$inpat =~ s:([^\\])/$:$1:;
			if ($inpat ne "") {
			    eval '$inpat =~ m'."\a$inpat\a";	
			    if ($@ ne "") {
				print $OUT "$@";
				next CMD;
			    }
			    $pat = $inpat;
			}
			$end = $start;
			eval '
			    for (;;) {
				++$start;
				$start = 1 if ($start > $max);
				last if ($start == $end);
				if ($dbline[$start] =~ m' . "\a$pat\a" . 'i) {
				    if ($emacs) {
					print $OUT "\032\032$filename:$start:0\n";
				    } else {
					print $OUT "$start:\t", $dbline[$start], "\n";
				    }
				    last;
				}
			    } ';
			print $OUT "/$pat/: not found\n" if ($start == $end);
			next CMD; };
		    $cmd =~ /^\?(.*)$/ && do {
			$inpat = $1;
			$inpat =~ s:([^\\])\?$:$1:;
			if ($inpat ne "") {
			    eval '$inpat =~ m'."\a$inpat\a";	
			    if ($@ ne "") {
				print $OUT "$@";
				next CMD;
			    }
			    $pat = $inpat;
			}
			$end = $start;
			eval '
			    for (;;) {
				--$start;
				$start = $max if ($start <= 0);
				last if ($start == $end);
				if ($dbline[$start] =~ m' . "\a$pat\a" . 'i) {
				    if ($emacs) {
					print $OUT "\032\032$filename:$start:0\n";
				    } else {
					print $OUT "$start:\t", $dbline[$start], "\n";
				    }
				    last;
				}
			    } ';
			print $OUT "?$pat?: not found\n" if ($start == $end);
			next CMD; };
		    $cmd =~ /^$rc+\s*(-)?(\d+)?$/ && do {
			pop(@hist) if length($cmd) > 1;
			$i = $1 ? ($#hist-($2?$2:1)) : ($2?$2:$#hist);
			$cmd = $hist[$i] . "\n";
			print $OUT $cmd;
			redo CMD; };
		    $cmd =~ /^$sh$sh\s*/ && do {
			&system($');
			next CMD; };
		    $cmd =~ /^$rc([^$rc].*)$/ && do {
			$pat = "^$1";
			pop(@hist) if length($cmd) > 1;
			for ($i = $#hist; $i; --$i) {
			    last if $hist[$i] =~ /$pat/;
			}
			if (!$i) {
			    print $OUT "No such command!\n\n";
			    next CMD;
			}
			$cmd = $hist[$i] . "\n";
			print $OUT $cmd;
			redo CMD; };
		    $cmd =~ /^$sh$/ && do {
			&system($ENV{SHELL}||"/bin/sh");
			next CMD; };
		    $cmd =~ /^$sh\s*/ && do {
			&system($ENV{SHELL}||"/bin/sh","-c",$');
			next CMD; };
		    $cmd =~ /^H\b\s*(-(\d+))?/ && do {
			$end = $2?($#hist-$2):0;
			$hist = 0 if $hist < 0;
			for ($i=$#hist; $i>$end; $i--) {
			    print $OUT "$i: ",$hist[$i],"\n"
			      unless $hist[$i] =~ /^.?$/;
			};
			next CMD; };
		    $cmd =~ s/^p$/print \$DB::OUT \$_/;
		    $cmd =~ s/^p\b/print \$DB::OUT /;
		    $cmd =~ /^=/ && do {
			if (local($k,$v) = ($cmd =~ /^=\s*(\S+)\s+(.*)/)) {
			    $alias{$k}="s~$k~$v~";
			    print $OUT "$k = $v\n";
			} elsif ($cmd =~ /^=\s*$/) {
			    foreach $k (sort keys(%alias)) {
				if (($v = $alias{$k}) =~ s~^s\~$k\~(.*)\~$~$1~) {
				    print $OUT "$k = $v\n";
				} else {
				    print $OUT "$k\t$alias{$k}\n";
				};
			    };
			};
			next CMD; };
		    $cmd =~ /^\|\|?\s*[^|]/ && do {
			if ($pager =~ /^\|/) {
			    open(SAVEOUT,">&STDOUT") || &warn("Can't save STDOUT");
			    open(STDOUT,">&OUT") || &warn("Can't redirect STDOUT");
			} else {
			    open(SAVEOUT,">&OUT") || &warn("Can't save DB::OUT");
			}
			unless ($piped=open(OUT,$pager)) {
			    &warn("Can't pipe output to `$pager'");
			    if ($pager =~ /^\|/) {
				open(OUT,">&STDOUT") || &warn("Can't restore DB::OUT");
				open(STDOUT,">&SAVEOUT")
				  || &warn("Can't restore STDOUT");
				close(SAVEOUT);
			    } else {
				open(OUT,">&STDOUT") || &warn("Can't restore DB::OUT");
			    }
			    next CMD;
			}
			$SIG{PIPE}= "DB::catch" if $pager =~ /^\|/
			  && "" eq $SIG{PIPE}  ||  "DEFAULT" eq $SIG{PIPE};
			$selected= select(OUT);
			$|= 1;
			select( $selected ), $selected= "" unless $cmd =~ /^\|\|/;
			$cmd =~ s/^\|+\s*//;
			redo PIPE; };
		    # XXX Local variants do not work!
		    $cmd =~ s/^t\s/\$DB::trace = 1;\n/;
		    $cmd =~ s/^s\s/\$DB::single = 1;\n/ && do {$laststep = 's'};
		    $cmd =~ s/^n\s/\$DB::single = 2;\n/ && do {$laststep = 'n'};
		}		# PIPE:
	    }			# <-- Do we know what this brace is for?
	    $evalarg = "\$^D = \$^D | \$DB::db_stop;\n$cmd"; &eval;
	    if ($onetimeDump) {
		$onetimeDump = undef;
	    } else {
		print $OUT "\n";
	    }
	} continue {		# CMD:
	    if ($piped) {
		if ($pager =~ /^\|/) {
		    $?= 0;  close(OUT) || &warn("Can't close DB::OUT");
		    &warn( "Pager `$pager' failed: ",
			  ($?>>8) > 128 ? ($?>>8)-256 : ($?>>8),
			  ( $? & 128 ) ? " (core dumped)" : "",
			  ( $? & 127 ) ? " (SIG ".($?&127).")" : "", "\n" ) if $?;
		    open(OUT,">&STDOUT") || &warn("Can't restore DB::OUT");
		    open(STDOUT,">&SAVEOUT") || &warn("Can't restore STDOUT");
		    $SIG{PIPE}= "DEFAULT" if $SIG{PIPE} eq "DB::catch";
		    # Will stop ignoring SIGPIPE if done like nohup(1)
		    # does SIGINT but Perl doesn't give us a choice.
		} else {
		    open(OUT,">&SAVEOUT") || &warn("Can't restore DB::OUT");
		}
		close(SAVEOUT);
		select($selected), $selected= "" unless $selected eq "";
		$piped= "";
	    }
	}			# CMD:
	if ($post) {
	    $evalarg = $post; &eval;
	}
    }				# if ($single || $signal)
    ($@, $!, $,, $/, $\, $^W) = @saved;
    ();
}

sub save {
    @saved = ($@, $!, $,, $/, $\, $^W);
    $, = ""; $/ = "\n"; $\ = ""; $^W = 0;
}

# The following takes its argument via $evalarg to preserve current @_

sub eval {
    my @res;
    {
	local (@stack) = @stack; # guard against recursive debugging
	my $otrace = $trace;
	my $osingle = $single;
	my $od = $^D;
	@res = eval "$usercontext $evalarg;\n"; # '\n' for nice recursive debug
	$trace = $otrace;
	$single = $osingle;
	$^D = $od;
    }
    my $at = $@;
    eval "&DB::save";
    if ($at) {
	print $OUT $at;
    } elsif ($onetimeDump) {
	dumpit(\@res);
    }
}

sub dumpit {
    local ($savout) = select($OUT);
    do 'dumpvar.pl' unless defined &main::dumpValue;
    if (defined &main::dumpValue) {
	&main::dumpValue(shift);
    } else {
	print $OUT "dumpvar.pl not available.\n";
    }
    select ($savout);    
}

sub action {
    my $action = shift;
    while ($action =~ s/\\$//) {
	#print $OUT "+ ";
	#$action .= "\n";
	$action .= &gets;
    }
    $action;
}

sub gets {
    local($.);
    #<IN>;
    $term->readline("cont: ");
}

sub system {
    # We save, change, then restore STDIN and STDOUT to avoid fork() since
    # many non-Unix systems can do system() but have problems with fork().
    open(SAVEIN,"<&STDIN") || &warn("Can't save STDIN");
    open(SAVEOUT,">&OUT") || &warn("Can't save STDOUT");
    open(STDIN,"<&IN") || &warn("Can't redirect STDIN");
    open(STDOUT,">&OUT") || &warn("Can't redirect STDOUT");
    system(@_);
    open(STDIN,"<&SAVEIN") || &warn("Can't restore STDIN");
    open(STDOUT,">&SAVEOUT") || &warn("Can't restore STDOUT");
    close(SAVEIN); close(SAVEOUT);
    &warn( "(Command returned ", ($?>>8) > 128 ? ($?>>8)-256 : ($?>>8), ")",
	  ( $? & 128 ) ? " (core dumped)" : "",
	  ( $? & 127 ) ? " (SIG ".($?&127).")" : "", "\n" ) if $?;
    $?;
}

sub setterm {
    eval "require Term::ReadLine;" or die $@;
    if ($notty) {
	if ($tty) {
	    open(IN,"<$tty") or die "Cannot open TTY `$TTY' for read: $!";
	    open(OUT,">$tty") or die "Cannot open TTY `$TTY' for write: $!";
	    $IN = \*IN;
	    $OUT = \*OUT;
	    my $sel = select($OUT);
	    $| = 1;
	    select($sel);
	} else {
	    eval "require Term::Rendezvous;" or die $@;
	    my $rv = $ENV{PERLDB_NOTTY} || "/tmp/perldbtty$$";
	    my $term_rv = new Term::Rendezvous $rv;
	    $IN = $term_rv->IN;
	    $OUT = $term_rv->OUT;
	}
    }
    if (!$rl) {
	$term = new Term::ReadLine::Stub 'perldb', $IN, $OUT;
    } else {
	$term = new Term::ReadLine 'perldb', $IN, $OUT;
    }
    $LINEINFO = $OUT unless defined $LINEINFO;
    $lineinfo = $console unless defined $lineinfo;
    $term->MinLine(2);
}

sub dump_option {
    my ($opt, $val)= @_;
    if (defined $optionAction{$opt}
	and defined &{$optionAction{$opt}}) {
	$val = &{$optionAction{$opt}}();
    } elsif (defined $optionAction{$opt}
	     and not defined $option{$opt}) {
	$val = 'N/A';
    } else {
	$val = $option{$opt};
    }
    $val =~ s/[\\\']/\\$&/g;
    printf $OUT "%20s = '%s'\n", $opt, $val;
}

sub parse_options {
    local($_)= @_;
    while ($_ ne "") {
	s/^(\w+)(\s*$|\W)// or print($OUT "Invalid option `$_'\n"), last;
	my ($opt,$sep) = ($1,$2);
	my $val;
	if ("?" eq $sep) {
	    print($OUT "Option query `$opt?' followed by non-space `$_'\n"), last
	      if /^\S/;
	    #&dump_option($opt);
	} elsif ($sep !~ /\S/) {
	    $val = "1";
	} elsif ($sep eq "=") {
	    s/^(\S*)($|\s+)//;
	    $val = $1;
	} else {
	    my ($end) = "\\" . substr( ")]>}$sep", index("([<{",$sep), 1 );
	    s/^(([^\\$end]|\\[\\$end])*)$end($|\s+)// or
	      print($OUT "Unclosed option value `$opt$sep$_'\n"), last;
	    $val = $1;
	    $val =~ s/\\([\\$end])/$1/g;
	}
	my ($option);
	my $matches =
	  grep(  /^\Q$opt/ && ($option = $_),  @options  );
	$matches =  grep(  /^\Q$opt/i && ($option = $_),  @options  )
	  unless $matches;
	print $OUT "Unknown option `$opt'\n" unless $matches;
	print $OUT "Ambiguous option `$opt'\n" if $matches > 1;
	$option{$option} = $val if $matches == 1 and defined $val;
	eval "require '$optionRequire{$option}'"
	  if $matches == 1 and defined $optionRequire{$option} and defined $val;
	&{$optionAction{$option}} ($val) 
	  if $matches == 1
	    and defined $optionAction{$option}
	      and defined &{$optionAction{$option}} and defined $val;
	&dump_option($option) if $matches == 1 && $OUT ne \*STDERR; # Not $rcfile
    }
}

sub catch {
    $signal = 1;
}

sub warn {
    my($msg)= join("",@_);
    $msg .= ": $!\n" unless $msg =~ /\n$/;
    print $OUT $msg;
}

sub sub {
    push(@stack, $single);
    $single &= 1;
    $single |= 4 if $#stack == $deep;
    if (wantarray) {
	@ret = &$sub;
	$single |= pop(@stack);
	$retctx = "list";
	$lastsub = $sub;
	@ret;
    } else {
	$ret = &$sub;
	$single |= pop(@stack);
	$retctx = "scalar";
	$lastsub = $sub;
	$ret;
    }
}

sub TTY {
    if ($term) {
	&warn("Too late to set TTY!\n") if @_;
    } else {
	$tty = shift if @_;
    }
    $tty or $console;
}

sub noTTY {
    if ($term) {
	&warn("Too late to set noTTY!\n") if @_;
    } else {
	$notty = shift if @_;
    }
    $notty;
}

sub ReadLine {
    if ($term) {
	&warn("Too late to set ReadLine!\n") if @_;
    } else {
	$rl = shift if @_;
    }
    $rl;
}

sub NonStop {
    if ($term) {
	&warn("Too late to set up NonStop mode!\n") if @_;
    } else {
	$runnonstop = shift if @_;
    }
    $runnonstop;
}

sub pager {
    if (@_) {
	$pager = shift;
	$pager="|".$pager unless $pager =~ /^(\+?\>|\|)/;
    }
    $pager;
}

sub shellBang {
    if (@_) {
	$sh = quotemeta shift;
	$sh .= "\\b" if $sh =~ /\w$/;
    }
    $psh = $sh;
    $psh =~ s/\\b$//;
    $psh =~ s/\\(.)/$1/g;
    &sethelp;
    $psh;
}

sub recallCommand {
    if (@_) {
	$rc = quotemeta shift;
	$rc .= "\\b" if $rc =~ /\w$/;
    }
    $prc = $rc;
    $prc =~ s/\\b$//;
    $prc =~ s/\\(.)/$1/g;
    &sethelp;
    $prc;
}

sub LineInfo {
    return $lineinfo unless @_;
    $lineinfo = shift;
    my $stream = ($lineinfo =~ /^(\+?\>|\|)/) ? $lineinfo : ">$lineinfo";
    $emacs = ($stream =~ /^\|/);
    open(LINEINFO, "$stream") || &warn("Cannot open `$stream' for write");
    $LINEINFO = \*LINEINFO;
    my $save = select($LINEINFO);
    $| = 1;
    select($save);
    $lineinfo;
}

sub sethelp {
    $help = "
T		Stack trace.
s [expr]	Single step [in expr].
n [expr]	Next, steps over subroutine calls [in expr].
<CR>		Repeat last n or s command.
r		Return from current subroutine.
c [line]	Continue; optionally inserts a one-time-only breakpoint
		at the specified line.
l min+incr	List incr+1 lines starting at min.
l min-max	List lines min through max.
l line		List single line.
l subname	List first window of lines from subroutine.
l		List next window of lines.
-		List previous window of lines.
w [line]	List window around line.
f filename	Switch to viewing filename.
/pattern/	Search forwards for pattern; final / is optional.
?pattern?	Search backwards for pattern; final ? is optional.
L		List all breakpoints and actions.
S [[!]pattern]	List subroutine names [not] matching pattern.
t		Toggle trace mode.
t expr		Trace through execution of expr.
b [line] [condition]
		Set breakpoint; line defaults to the current execution line;
		condition breaks if it evaluates to true, defaults to '1'.
b subname [condition]
		Set breakpoint at first line of subroutine.
d [line]	Delete the breakpoint for line.
D		Delete all breakpoints.
a [line] command
		Set an action to be done before the line is executed.
		Sequence is: check for breakpoint, print line if necessary,
		do action, prompt user if breakpoint or step, evaluate line.
A		Delete all actions.
V [pkg [vars]]	List some (default all) variables in package (default current).
		Use ~pattern and !pattern for positive and negative regexps.
X [vars]	Same as \"V currentpackage [vars]\".
x expr		Evals expression in array context, dumps the result.
O [opt[=val]] [opt\"val\"] [opt?]...
		Set or query values of options.  val defaults to 1.  opt can
		be abbreviated.  Several options can be listed.
    recallCommand, shellBang:	chars used to recall command or spawn shell;
    pager:			program for output of \"|cmd\";
  The following options affect what happens with V, X, and x commands:
    arrayDepth, hashDepth:	print only first N elements ('' for all);
    compactDump, veryCompact:	change style of array and hash dump;
    globPrint:			whether to print contents of globs;
    DumpDBFiles:		dump arrays holding debugged files;
    dumpPackages:		dump symbol tables of packages;
    quote, HighBit, undefPrint:	change style of string dump;
  Option PrintRet affects printing of return value after r command.
		During startup options are initialized from \$ENV{PERLDB_OPTS}.
		You can put additional initialization options TTY, noTTY,
		ReadLine, and NonStop there.
< command	Define command to run before each prompt.
> command	Define command to run after each prompt.
$prc number	Redo a previous command (default previous command).
$prc -number	Redo number'th-to-last command.
$prc pattern	Redo last command that started with pattern.
$psh$psh cmd  	Run cmd in a subprocess (reads from DB::IN, writes to DB::OUT)"
  . ( $rc eq $sh ? "" : "
$psh [cmd] 	Run cmd in subshell (forces \"\$SHELL -c 'cmd'\")." ) . "
H -number	Display last number commands (default all).
p expr		Same as \"print DB::OUT expr\" in current package.
|dbcmd		Run debugger command, piping DB::OUT to current pager.
||dbcmd		Same as |dbcmd but DB::OUT is temporarilly select()ed as well.
\= [alias value]	Define a command alias, or list current aliases.
command		Execute as a perl statement in current package.
h [db_command]	Get help on a specific debugger command (\"h h\" for summary).
q or ^D		Quit.

";
    $summary = <<"END_SUM";
List/search source lines:               Control script execution:
  l [ln|sub]  List source code            T           Stack trace
  -           List previous lines         s [expr]    Single step [in expr]
  w [line]    List around line            n [expr]    Next, steps over subs
  f filename  View source in file         <CR>        Repeat last n or s
  /pattern/   Search forward              r           Return from subroutine
  ?pattern?   Search backward             c [line]    Continue until line
Debugger controls:                        L           List break pts & actions
  O [...]     Set debugger options        t [expr]    Toggle trace [trace expr]
  < command   Command for before prompt   b [ln] [c]  Set breakpoint
  > command   Command for after prompt    b sub [c]   Set breakpoint for sub
  $prc [N|pat]   Redo a previous command     d [line]    Delete a breakpoint
  H [-num]    Display last num commands   D           Delete all breakpoints
  = [a val]   Define/list an alias        a [ln] cmd  Do cmd before line
  h [db_cmd]  Get help on command         A           Delete all actions
  |[|]dbcmd   Send output to pager        command     Execute perl code
  q or ^D     Quit                        ![!] cmd    Run cmd in a subprocess
Information about variables:
  S [[!]pat]  List subroutine names [not] matching pattern
  V [P [Vs]]  List Variables in Package.  Vs can be ~pattern or !pattern.
  X [vars]    Same as \"V current_package [vars]\".
  x expr      Evals expression in array context, dumps the result.
  p expr      Print expression (uses script's current package).
END_SUM
				# '); # Fix balance of Emacs parsing
}

1;
