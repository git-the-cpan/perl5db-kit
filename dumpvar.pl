package dumpvar;

# Needed for PrettyPrinter only:

# require 5.001;  # Well, it coredumps anyway undef DB in 5.000 (not now)

# translate control chars to ^X - Randal Schwartz
# Modifications to print types by Peter Gordon v1.0
# Won't dump symbol tables and contents of debugged files by default

$winsize = 80;


# Defaults

# $globPrint = 1;
$printUndef = 1;
$tick = "'";
$unctrl = 'quote';

sub main::dumpValue {
  local %address;
  (print "undef\n"), return unless defined $_[0];
  (print &stringify($_[0]), "\n"), return unless defined ref $_[0];
  dumpvar::unwrap($_[0],0);
}

# This one is good for variable names:

sub unctrl {
	local($_) = @_;
	local($v) ; 

	return \$_ if ref \$_ eq "GLOB";
	s/([\001-\037\177])/'^'.pack('c',ord($1)^64)/eg;
	$_;
}

sub stringify {
	local($_,$noticks) = @_;
	local($v) ; 

	return 'undef' unless defined $_ or not $printUndef;
	return $_ . "" if ref \$_ eq 'GLOB';
	if ($tick eq "'") {
	  s/([\'\\])/\\$1/g if $tick eq '\'';
	} elsif ($unctrl eq 'unctrl') {
	  s/([\"\\])/\\$1/g ;
	  s/([\001-\037\177])/'^'.pack('c',ord($1)^64)/eg;
	  s/([\200-\377])/'\\0x'.sprintf('%2X',ord($1))/eg 
	    if $quoteHighBit;
	} elsif ($unctrl eq 'quote') {
	  s/([\"\\\$\@])/\\$1/g if $tick eq '"';
	  s/\033/\\e/g;
	  s/([\001-\037\177])/'\\c'.chr(ord($1)^64)/eg;
	}
	s/([\200-\377])/'\\'.sprintf('%3o',ord($1))/eg if $quoteHighBit;
	($noticks || /^\d+(\.\d*)?\Z/) 
	  ? $_ 
	  : $tick . $_ . $tick;
}

sub ShortArray {
  my $tArrayDepth = $#{$_[0]} ; 
  $tArrayDepth = $#{$_[0]} < $arrayDepth-1 ? $#{$_[0]} : $arrayDepth-1 
    unless  $arrayDepth eq '' ; 
  my $shortmore = "";
  $shortmore = " ..." if $tArrayDepth < $#{$_[0]} ;
  if (!grep(ref $_, @{$_[0]})) {
    $short = "0..$#{$_[0]}  '" . 
      join("' '", @{$_[0]}[0..$tArrayDepth]) . "'$shortmore";
    return $short if length $short <= $compactDump;
  }
  undef;
}

sub DumpElem {
  my $short = &stringify($_[0], defined ref $_[0]);
  if ($veryCompact && ref $_[0]
      && (ref $_[0] eq 'ARRAY' and !grep(ref $_, @{$_[0]}) )) {
    my $end = "0..$#{$v}  '" . 
      join("' '", @{$_[0]}[0..$tArrayDepth]) . "'$shortmore";
  } elsif ($veryCompact && ref $_[0]
      && (ref $_[0] eq 'HASH') and !grep(ref $_, values %{$_[0]})) {
    my $end = 1;
	  $short = $sp . "0..$#{$v}  '" . 
	    join("' '", @{$v}[0..$tArrayDepth]) . "'$shortmore";
  } else {
    print "$short\n";
    unwrap($_[0],$_[1]);
  }
}

sub unwrap {
    return if $DB::signal;
    local($v) = shift ; 
    local($s) = shift ; # extra no of spaces
    local(%v,@v,$sp,$value,$key,$type,@sortKeys,$more,$shortmore,$short) ;
    local($tHashDepth,$tArrayDepth) ;

    $sp = " " x $s ;
    $s += 3 ; 

    # Check for reused addresses
    if (defined ref $v) { 
      ($address) = $v =~ /(0x[0-9a-f]+)/ ; 
      if (defined $address) { 
	($type) = $v =~ /=(.*?)\(/ ;
	$address{$address}++ ;
	if ( $address{$address} > 1 ) { 
	  print "${sp}-> REUSED_ADDRESS\n" ; 
	  return ; 
	} 
      }
    } elsif (ref \$v eq 'GLOB') {
      $address = "$v" . "";	# To avoid a bug with globs
      $address{$address}++ ;
      if ( $address{$address} > 1 ) { 
	print "${sp}*DUMPED_GLOB*\n" ; 
	return ; 
      } 
    }

    if ( ref $v eq 'HASH' or $type eq 'HASH') { 
	@sortKeys = sort keys(%$v) ;
	undef $more ; 
	$tHashDepth = $#sortKeys ; 
	$tHashDepth = $#sortKeys < $hashDepth-1 ? $#sortKeys : $hashDepth-1
	  unless $hashDepth eq '' ; 
	$more = "....\n" if $tHashDepth < $#sortKeys ; 
	$shortmore = "";
	$shortmore = ", ..." if $tHashDepth < $#sortKeys ; 
	$#sortKeys = $tHashDepth ; 
	if ($compactDump && !grep(ref $_, values %{$v})) {
	  #$short = $sp . 
	  #  (join ', ', 
# Next row core dumps during require from DB on 5.000, even with map {"_"}
	  #   map {&stringify($_) . " => " . &stringify($v->{$_})} 
	  #   @sortKeys) . "'$shortmore";
	  $short = $sp;
	  my @keys;
	  for (@sortKeys) {
	    push @keys, &stringify($_) . " => " . &stringify($v->{$_});
	  }
	  $short .= join ', ', @keys;
	  $short .= $shortmore;
	  (print "$short\n"), return if length $short <= $compactDump;
	}
	for $key (@sortKeys) {
	    return if $DB::signal;
	    $value = $ {$v}{$key} ;
	    print "$sp", &stringify($key), " => ";
	    DumpElem $value, $s;
	}
	print "$sp$more" if defined $more ;
    } elsif ( ref $v eq 'ARRAY' or $type eq 'ARRAY') { 
	$tArrayDepth = $#{$v} ; 
	undef $more ; 
	$tArrayDepth = $#{$v} < $arrayDepth-1 ? $#{$v} : $arrayDepth-1 
	  unless  $arrayDepth eq '' ; 
	$more = "....\n" if $tArrayDepth < $#{$v} ; 
	$shortmore = "";
	$shortmore = " ..." if $tArrayDepth < $#{$v} ;
	if ($compactDump && !grep(ref $_, @{$v})) {
	  if ($#$v >= 0) {
	    $short = $sp . "0..$#{$v}  '" . 
	      join("' '", @{$v}[0..$tArrayDepth]) . "'$shortmore";
	  } else {
	    $short = $sp . "empty array";
	  }
	  (print "$short\n"), return if length $short <= $compactDump;
	}
	#if ($compactDump && $short = ShortArray($v)) {
	#  print "$short\n";
	#  return;
	#}
	for $num ($[ .. $tArrayDepth) {
	    return if $DB::signal;
	    print "$sp$num  ";
	    DumpElem $v->[$num], $s;
	}
	print "$sp$more" if defined $more ;  
    } elsif ( ref $v eq 'SCALAR' or ref $v eq 'REF' or $type eq 'SCALAR' ) { 
	    print "$sp-> ";
	    DumpElem $$v, $s;
    } elsif (ref $v eq 'GLOB') {
      print "$sp-> ",&stringify($$v,1),"\n";
      if ($globPrint) {
	$s += 3;
	dumpglob($s, "{$$v}", $$v, 1);
      } elsif (defined ($fileno = fileno($v))) {
	print( (' ' x ($s+3)) .  "FileHandle({$$v}) => fileno($fileno)\n" );
      }
    } elsif (ref \$v eq 'GLOB') {
      if ($globPrint) {
	dumpglob($s, "{$v}", $v, 1) if $globPrint;
      } elsif (defined ($fileno = fileno(\$v))) {
	print( (' ' x $s) .  "FileHandle({$v}) => fileno($fileno)\n" );
      }
    }
}

sub matchvar {
  $_[0] eq $_[1] or 
    ($_[1] =~ /^([!~])(.)/) and 
      ($1 eq '!') ^ (eval {($_[2] . "::" . $_[0]) =~ /$2$'/});
}

sub arrayDepth {
  $arrayDepth = shift if @_;
  $arrayDepth;
}

sub hashDepth {
  $hashDepth = shift if @_;
  $hashDepth;
}

sub dumpDBFiles {
  $dumpDBFiles = shift if @_;
  $dumpDBFiles;
}

sub dumpPackages {
  $dumpPackages = shift if @_;
  $dumpPackages;
}

sub compactDump {
  $compactDump = shift if @_;
  $compactDump = 6*80-1 if $compactDump and $compactDump < 2;
  $compactDump;
}

sub veryCompact {
  $veryCompact = shift if @_;
  compactDump(1) if !$compactDump and $veryCompact;
  $veryCompact;
}

sub unctrlSet {
  if (@_) {
    my $in = shift;
    if ($in eq 'unctrl' or $in eq 'quote') {
      $unctrl = $in;
    } else {
      print "Unknown value for `unctrl'.\n";
    }
  }
  $unctrl;
}

sub tick {
  $tick = shift if @_;
  $tick;
}

sub quote {
  if ($_[0]) {
    $tick = '"';
    $unctrl = 'quote';
  } elsif (@_) {		# Need to set
    $tick = "'";
    $unctrl = 'unctrl';
  }
  $tick;
}

sub quoteHighBit {
  $quoteHighBit = shift if @_;
  $quoteHighBit;
}

sub printUndef {
  $printUndef = shift if @_;
  $printUndef;
}

sub globPrint {
  $globPrint = shift if @_;
  $globPrint;
}

sub dumpglob {
    return if $DB::signal;
    my ($off,$key, $val, $all) = @_;
    local(*entry) = $val;
    my $fileno;
    if (defined $entry) {
      print( (' ' x $off) . "\$", &unctrl($key), " = " );
      DumpElem $entry, 3+$off;
    }
    if (($key !~ /^_</ or $dumpDBFiles) and defined @entry) {
      print( (' ' x $off) . "\@$key = (\n" );
      unwrap(\@entry,3+$off) ;
      print( (' ' x $off) .  ")\n" );
    }
    if ($key ne "main::" && $key ne "DB::" && defined %entry
	&& ($dumpPackages or $key !~ /::$/)
	&& !($package eq "dumpvar" and $key eq "stab")) {
      print( (' ' x $off) . "\%$key = (\n" );
      unwrap(\%entry,3+$off) ;
      print( (' ' x $off) .  ")\n" );
    }
    if (defined ($fileno = fileno(*entry))) {
      print( (' ' x $off) .  "FileHandle($key) => fileno($fileno)\n" );
    }
    if ($all) {
      if (defined &entry) {
	my $sub = $key;
	$sub = $1 if $sub =~ /^\{\*(.*)\}$/;
	my $place = $DB::sub{$sub};
	$place = '???' unless defined $place;
	print( (' ' x $off) .  "&$sub in $place\n" );
      }
    }
}

sub main::dumpvar {
    my ($package,@vars) = @_;
    local(%address,$key,$val);
    $package .= "::" unless $package =~ /::$/;
    *stab = *{"main::"};
    while ($package =~ /(\w+?::)/g){
      *stab = $ {stab}{$1};
    }
    while (($key,$val) = each(%stab)) {
      return if $DB::signal;
      next if @vars && !grep( matchvar($key, $_), @vars );
      dumpglob(0,$key, $val);
    }
}


