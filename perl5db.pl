package DB;

# modified Perl debugger, to be run from Emacs in perldb-mode
# Ray Lischner (uunet!mntgfx!lisch) as of 5 Nov 1990
# Johan Vromans -- upgrade to 4.0 pl 10

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
# At start reads environment variable PERLDB_OPTS and parses it as a
# rest of `O ...' line in debugger prompt. 
#
# The options that can be specified only at startup: 
# 
# TTY  - the TTY to use for debugging i/o
#
# noTTY - if set, goes in NonStop mode. On interrupt if TTY is not set
# uses the value of noTTY or "/tmp/perldbtty$$" to find TTY using
# Term::Rendezvous. Current variant is to have the name of TTY in this
# file. 
#
# ReadLine - If false, dummy ReadLine is used, so you can debug
# ReadLine applications.
#
# NonStop - if true, no i/o is performed until interrupt.
# 
# LineInfo - file or pipe to print line number info to. If it is a
# pipe, a short "emacs like" message is used.

local($^W) = 0;
    
@options = qw(hashDepth arrayDepth dumpDBFiles dumpPackages compactDump
	      veryCompact quote highBit undefPrint globPrint TTY noTTY 
	      ReadLine NonStop LineInfo);
%optionAction = (
		 hashDepth	=> \&dumpvar::hashDepth, 
		 arrayDepth	=> \&dumpvar::arrayDepth,
		 dumpDBFiles	=> \&dumpvar::dumpDBFiles,
		 dumpPackages	=> \&dumpvar::dumpPackages,
		 compactDump	=> \&dumpvar::compactDump,
		 veryCompact	=> \&dumpvar::veryCompact,
		 quote		=> \&dumpvar::quote,
		 highBit	=> \&dumpvar::quoteHighBit,
		 undefPrint	=> \&dumpvar::printUndef,
		 globPrint	=> \&dumpvar::globPrint,
		 TTY		=> \&tty,
		 noTTY		=> \&notty,
		 ReadLine	=> \&rl,
		 NonStop	=> \&nonstop,
		 LineInfo	=> \&lineinfo,
		);
%optionRequire = (
		  hashDepth	=> 'dumpvar.pl', 
		  arrayDepth	=> 'dumpvar.pl',
		  dumpDBFiles	=> 'dumpvar.pl',
		  dumpPackages	=> 'dumpvar.pl',
		  compactDump	=> 'dumpvar.pl',
		  veryCompact	=> 'dumpvar.pl',
		  quote		=> 'dumpvar.pl',
		  highBit	=> 'dumpvar.pl',
		  undefPrint	=> 'dumpvar.pl',
		  globPrint	=> 'dumpvar.pl',
		  );

$rl = 1 unless defined $rl;

if (defined $ENV{PERLDB_OPTS}) {
  parse_options(split(' ', $ENV{PERLDB_OPTS}));
}

if ($notty) {
  $runnonstop = 1;
} else {
  # Is Perl being run from Emacs?
  $emacs = ((defined $main::ARGV[0]) and ($main::ARGV[0] eq '-emacs'));
  shift(@main::ARGV) if $emacs;
  
  #require Term::ReadLine;
  
  local($^W) = 0;
  
  if (-e "/dev/tty") {
    $console = "/dev/tty";
    $rcfile=".perldb";
  }
  elsif (-e "con") {
    $console = "con";
    $rcfile="perldb.ini";
  }
  else {
    $console = "sys\$command";
    $rcfile="perldb.ini";
  }
  
  # Around a bug:
  if (defined $ENV{'OS2_SHELL'}) { # In OS/2
    if ($DB::emacs) {
      $console = undef;
    } else {
      $console = "/dev/con";
    }
  }
  
  $console = $tty if defined $tty;
  
  open(IN, "<$console") || open(IN,  "<&STDIN"); # so we don't dingle stdin
  $IN = \*IN;
  
  open(OUT,">$console") || open(OUT, ">&STDERR")
    || open(OUT, ">&STDOUT");	# so we don't dongle stdout
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
    print $OUT "\nEnter h for help.\n\n";
  }
} 

$sub = '';
    
$help = "
T		Stack trace.
s [expr]	Single step (in expr).
n [expr]	Next, steps over subroutine calls (in expr).
r		Return from current subroutine.
c [line]	Continue; optionally inserts a one-time-only breakpoint 
		at the specified line.
<CR>		Repeat last n or s.
l min+incr	List incr+1 lines starting at min.
l min-max	List lines.
l line		List line;
l		List next window.
-		List previous window.
w line		List window around line.
l subname	List subroutine.
f filename	Switch to filename.
/pattern/	Search forwards for pattern; final / is optional.
?pattern?	Search backwards for pattern.
L		List breakpoints and actions.
S [[!]pattern]	List subroutine names.
t		Toggle trace mode.
t expr		Trace through execution of expr.
b [line] [condition]
		Set breakpoint; line defaults to the current execution line; 
		condition breaks if it evaluates to true, defaults to \'1\'.
b subname [condition]
		Set breakpoint at first line of subroutine.
d [line]	Delete breakpoint.
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
O [opt[=val]] ...
		Set or query values of options. val defaults to 1. opt can
		be abbreviated. Several options can be combined. Recognized
		options effect what happens with V,X and x commands:
		arrayDepth, hashDepth:	'' or number: elements to print;
		compactDump, veryCompact:
					change style of array and hash dump.
		globPrint		whether to print contents of globs
		dumpDBFiles:		dump arrays containing debugged files;
		dumpPackages:		dump symbolic tables of packages;
		quote, highBit, undefPrint:
					change style of string dump.
		During startup options are initialized from \$ENV{PERLDB_OPTS}.
		You can put additional initialization options TTY, noTTY,
		ReadLine, NonStop there.
< command	Define command before prompt.
> command	Define command after prompt.
! number	Redo command (default previous command).
! -number	Redo number\'th to last command.
H -number	Display last number commands (default all).
q or ^D		Quit.
p expr		Same as \"print DB::OUT expr\" in current package.
\= [alias value]	Define a command alias, or list current aliases.
command		Execute as a perl statement in current package.
h [debugger command]
		Get help on command.

";

$db_stop = 1 << 30;
$level = 0;			# Level of recursive debugging
@ARGS;

sub DB {
    if ($runnonstop) {		# Disable until signal
      for ($i=0; $i <= $#stack; ) {
	$stack[$i++] &= ~1;
      }
      $single = $runnonstop = 0; # Once only
      return;
    }
    &save;
    ($package, $filename, $line) = caller;
    $usercontext = '($@, $!, $,, $/, $\, $^W) = @saved;' .
	"package $package;";	# this won't let them modify, alas
    local(*dbline) = "::_<$filename";
    $max = $#dbline;
    if (($stop,$action) = split(/\0/,$dbline{$line})) {
	if ($stop eq '1') {
	    $signal |= 1;
	}
	else {
	    $evalarg = "\$DB::signal |= do {$stop;}"; &eval;
	    $dbline{$line} =~ s/;9($|\0)/$1/;
	}
    }
    if ($single || $trace || $signal) {
	$term || &setterm;
	if ($emacs) {
	    print $LINEINFO "\032\032$filename:$line:0\n";
	} else {
	    $prefix = $sub =~ /\'|::/ ? "" : "${package}::"; 
	    $prefix .= "$sub($filename:";
	    if (length($prefix) > 30) {
		print $LINEINFO "$prefix$line):\n$line:\t",$dbline[$line];
		$prefix = "";
		$infix = ":\t";
	    }
	    else {
		$infix = "):\t";
		print $LINEINFO "$prefix$line$infix",$dbline[$line];
	    }
	    for ($i = $line + 1; $i <= $max && $dbline[$i] == 0; ++$i) {
		last if $dbline[$i] =~ /^\s*(}|#|\n)/;
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
	    {
		$single = 0;
		$signal = 0;
		$cmd =~ s/\\$// && do {
		    $cmd .= $term->readline("  cont: ");
		    redo CMD;
		};
		$cmd =~ /^q$/ && exit 0;
		$cmd =~ /^$/ && ($cmd = $laststep);
		push(@hist,$cmd) if length($cmd) > 1;
		($i) = split(/\s+/,$cmd);
		eval "\$cmd =~ $alias{$i}", print $OUT $@ if $alias{$i};
		$cmd =~ /^h$/ && do {
		    print $OUT $help;
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
		$cmd =~ /^J\b\s*(\d+)/ && do {
			do 'dumpvar.pl' unless defined &main::dumpvar;
		        dumpvar::depth($1) ;
		        next CMD;};
		$cmd =~ /^J\s*$/ && do {
			do 'dumpvar.pl' unless defined &main::dumpvar;
		        dumpvar::noDepth() ;
		        next CMD;};
		$cmd =~ /^V\b\s*(\S+)\s*(.*)/ && do {
		    local ($savout) = select($OUT);
		    $packname = $1;
		    @vars = split(' ',$2);
		    do 'dumpvar.pl' unless defined &main::dumpvar;
		    if (defined &main::dumpvar) {
			&main::dumpvar($packname,@vars);
		    }
		    else {
			print $OUT "dumpvar.pl not available.\n";
		    }
		    select ($savout);
		    next CMD; };
		$cmd =~ s/^x\b/ / && do { # So that will be evaled
		    $onetimeDump = 1;
		    };
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
			print $OUT "There's no code here anything matching $file.\n";
			next CMD;
		    }
		    elsif ($file ne $filename) {
			*dbline = "::_<$file";
			$max = $#dbline;
			$filename = $file;
			$start = 1;
			$cmd = "l";
		    } };
		$cmd =~ /^l\b\s*([':A-Za-z_][':\w]*)/ && do {
		    $subname = $1;
		    $subname = "main::" . $subname unless $subname =~ /'|::/; #';
		    $subname = "main" . $subname if substr($subname,0,1)eq "'";
		    $subname = "main" . $subname if substr($subname,0,2)eq "::";
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
			print $OUT "Subroutine $1 not found.\n";
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
		    $start = $i;	# remember in case they want more
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
		    $subname = "${package}::" . $subname
			unless $subname =~ /\'|::/; 
		    $subname = "main" . $subname if substr($subname,0,1) eq "'";
		    $subname = "main" . $subname if substr($subname,0,2) eq "::";
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
		$cmd =~ /^O$/ && do {
		    my $val;
		    for (@options) {
		      if (defined $optionAction{$_}
			  and defined &{$optionAction{$_}}) {
			$val = &{$optionAction{$_}}();
		      } elsif (defined $optionAction{$_} 
			       and not defined $option{$_}) {
		      	$val = 'N/A';
		      } else {
			$val = $option{$_};
		      }
		      $val =~ s/[\\\']/\\$&/g;
		      print $OUT "\t$_='$val'\n";
		    } 
		    next CMD; };
		$cmd =~ /^O\s/ && do {
		    parse_options(split(' ',$'));
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
			if ($dbline[$start] =~ m'."\a$pat\a".'i) {
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
			if ($dbline[$start] =~ m'."\a$pat\a".'i) {
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
		$cmd =~ /^!+\s*(-)?(\d+)?$/ && do {
		    pop(@hist) if length($cmd) > 1;
		    $i = ($1?($#hist-($2?$2:1)):($2?$2:$#hist));
		    $cmd = $hist[$i] . "\n";
		    print $OUT $cmd;
		    redo CMD; };
		$cmd =~ /^!(.+)$/ && do {
		    $pat = "^$1";
		    pop(@hist) if length($cmd) > 1;
		    for ($i = $#hist; $i; --$i) {
			last if $hist[$i] =~ $pat;
		    }
		    if (!$i) {
			print $OUT "No such command!\n\n";
			next CMD;
		    }
		    $cmd = $hist[$i] . "\n";
		    print $OUT $cmd;
		    redo CMD; };
		$cmd =~ /^H\b\s*(-(\d+))?/ && do {
		    $end = $2?($#hist-$2):0;
		    $hist = 0 if $hist < 0;
		    for ($i=$#hist; $i>$end; $i--) {
			print $OUT "$i: ",$hist[$i],"\n"
			    unless $hist[$i] =~ /^.?$/;
		    };
		    next CMD; };
		$cmd =~ s/^p( .*)?$/print \$DB::OUT$1/;
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
		# XXX Local variants do not work!
		$cmd =~ s/^t\s/\$DB::trace = 1;\n/;
		$cmd =~ s/^s\s/\$DB::single = 1;\n/ && do {$laststep = 's'};
		$cmd =~ s/^n\s/\$DB::single = 2;\n/ && do {$laststep = 'n'};
	    }
	    $evalarg = "\$^D = \$^D | \$DB::db_stop;\n$cmd"; &eval;
	    if ($onetimeDump) {
	      $onetimeDump = undef;
	    } else {
	      print $OUT "\n";
	    }
	}
	if ($post) {
	    $evalarg = $post; &eval;
	}
    }
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
      local (@stack) = @stack;	# guard against recursive debugging
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
	local ($savout) = select($OUT);
	do 'dumpvar.pl' unless defined &main::dumpValue;
	if (defined &main::dumpValue) {
	  &main::dumpValue(\@res);
	}
	else {
	  print $OUT "dumpvar.pl not available.\n";
	}
	select ($savout);
    }
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
      my $rv = $ENV{PERLDB_NOTTY} or "/tmp/perldbtty$$";
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

sub parse_options {
  for (@_) {
    $_ .= "=1" unless /=/;
    my ($opt,$val, $option,$l) = /([^=]*)=(.*)/;
    $l = length $opt;
    my $matches = 
      grep length >= $l && substr($_,0,$l) eq $opt && ($option = $_), @options;
    print $OUT "Unknown option `$opt'\n" unless $matches;
    print $OUT "Ambiguous option `$opt'\n" if $matches > 1;
    $option{$option} = $val if $matches == 1;
    eval "require '$optionRequire{$option}'" 
      if $matches == 1 and defined $optionRequire{$option};
    &{$optionAction{$option}} ($val) if $matches == 1 
      && defined $optionAction{$option} and defined &{$optionAction{$option}};
  }
}

sub catch {
    $signal = 1;
}

sub sub {
    push(@stack, $single);
    $single &= 1;
    $single |= 4 if $#stack == $deep;
    if (wantarray) {
	@i = &$sub;
	$single |= pop(@stack);
	@i;
    }
    else {
	$i = &$sub;
	$single |= pop(@stack);
	$i;
    }
}

sub tty {
  if ($term) {
    warn "Too late to set TTY!\n" if @_;
  } else {
    $tty = shift if @_;
  }
  $tty or $console;
}

sub notty {
  if ($term) {
    warn "Too late to set TTY!\n" if @_;
  } else {
    $notty = shift if @_;
  }
  $notty;
}

sub rl {
  if ($term) {
    warn "Too late to set TTY!\n" if @_;
  } else {
    $rl = shift if @_;
  }
  $rl;
}

sub nonstop {
  if ($term) {
    warn "Too late to set up nonstop mode!\n" if @_;
  } else {
    $runnonstop = shift if @_;
  }
  $runnonstop;
}

sub lineinfo {
  return $lineinfo unless @_;
  $lineinfo = shift;
  my $stream = ($lineinfo =~ /^[>|]/) ? $lineinfo : ">$lineinfo";
  $emacs = ($stream =~ /^\|/);
  open(LINEINFO, ">$stream") || warn "Cannot open `$stream' for write: $!";
  $LINEINFO = \*LINEINFO;
  my $save = select($LINEINFO);
  $| = 1;
  select($save);
  $lineinfo;
}

$trace = $signal = $single = 0;	# uninitialized warning suppression

@hist = ('?');
$SIG{'INT'} = "DB::catch";
$deep = 100;		# warning if stack gets this deep
$window = 10;
$preview = 3;

@stack = (0);
@ARGS = @ARGV;
for (@args) {
    s/'/\\'/g;
    s/(.*)/'$1'/ unless /^-?[\d.]+$/;
}

if (-f $rcfile) {
    do "./$rcfile";
}
elsif (-f "$ENV{'LOGDIR'}/$rcfile") {
    do "$ENV{'LOGDIR'}/$rcfile";
}
elsif (-f "$ENV{'HOME'}/$rcfile") {
    do "$ENV{'HOME'}/$rcfile";
}

1;

