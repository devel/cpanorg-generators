#!/usr/bin/perl -w

use strict;

use File::Basename qw/basename/;

my @P;

if (open(my $f1, $ARGV[0])) {
    while(<$f1>) {
	chomp;
	push @P, [split(/:/)];
    }
} else {
    die "$ARGV[0]: $!\n";
}

if (open(my $f2, $ARGV[1])) {
    while (<$f2>) {
	print;
	if (/<!-- LATEST_RELEASES -->/) {
	    print qq[<table border="1">\n<tr><th>Release</th><th>File</th><th>Type</th><th>Age</th></tr>\n];
	    for my $r (@P) {
		my ($branch, $release, $file, $type, $pretty) = @$r;
		next unless $branch =~ /^\d/;
		next unless defined $file;
		my $f =
		    join(", ",
			 map {
			     my $b = basename($_);
			     qq[<a href="$b">$b</a>];
			 } split(/,/, $file));
		print qq[<tr><td>$branch</td><td>$release</td><td>$f</td><td>$type</td><td>$pretty</td></tr>\n];
	    }
	    print qq[</table>\n];
	}
    }
} else {
    die "$ARGV[1]: $!\n";
}

exit(0);
