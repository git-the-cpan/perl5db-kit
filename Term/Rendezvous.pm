package Term::Rendezvous;

sub new {
  shift;
  my $file = shift;
  my $tty;
  my $fail;
  if (-r $file and open(IN, $file)) {
    $tty = <IN>;
    chomp $tty;
    close(IN) or $fail = $!;
  }
  warn "tty `$tty' fail `$fail'\n";
  if (defined $tty and !$fail) {
    open(IN,  $tty);
    open(OUT, ">$tty");
  } else {
    # Is Perl being run from Emacs?
    $emacs = ((defined $main::ARGV[0]) and ($main::ARGV[0] eq '-emacs'));
    shift(@main::ARGV) if $emacs;
    
    if (-e "/dev/tty") {
      $console = "/dev/tty";
      $rcfile=".perldb";
    } elsif (-e "con") {
      $console = "con";
      $rcfile="perldb.ini";
    } else {
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
    
    $IN = IN;
    open(IN, "<$console") || open(IN,  "<&STDIN"); # so we don't dingle stdin
    
    $OUT = OUT;
    open(OUT,">$console") || open(OUT, ">&STDERR")
      || open(OUT, ">&STDOUT");	# so we don't dongle stdout
    my $out = select(OUT);
    $| = 1;			# for DB::OUT
    select($out);
    
    $| = 1;			# for real STDOUT
    warn "console `$console' " . fileno(OUT) . " " . fileno(IN) . "\n";
  }
  if ($fail) {
    print OUT "Close on `$file' failed: $fail\n";
  }
  print OUT "Connection established 1\n";
  return bless [\*IN,\*OUT];
}

sub IN {shift->[0]}
sub OUT {shift->[1]}

1;
