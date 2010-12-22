#!/usr/bin/perl -w

use strict;

use File::Spec;

die "$0: Usage: $0 output_file\n" unless @ARGV == 1;

my $output = shift(@ARGV);

my %CHECKSUM;

open(my $fh, ">$output") or die "$0: $output: $!\n";

sub emit {
    print $fh "@_\n";
}

emit("cd CPAN/src || exit 1");

my %Perl;

while (<>) {
    print;
    chomp;
    my ($label, @rest) = split(/:/);
    $Perl{$label} = [ @rest ];
}

sub emit_time_copy {
    my ($src, $dst) = @_;
    return unless defined $src && -f $src;
    emit(q[perl -e '$f=shift;($a,$m)=(stat($f))[8,9]; utime $a, $m, @ARGV'].qq[ $src $dst]);
}

sub emit_cksum {
    my ($d, $f, $label) = @_;
    for my $c (qw(md5 sha1 sha256)) { 
	my $CHECKSUMS = "${d}CHECKSUMS";
	unless (exists $CHECKSUM{$CHECKSUMS}) {
	    unless (defined($CHECKSUM{$CHECKSUMS} = do $CHECKSUMS)) {
		die "Checksums $CHECKSUMS not found\n";
	    }
	}
	my $cksum = $CHECKSUM{$CHECKSUMS}->{$f}->{$c};
	unless (defined $cksum) {
	    if (open(my $fh, "openssl $c $d/$f |")) {
		while (<$fh>) {
		    if (/^.+= (.+)$/) {
			$cksum = $1;
			last;
		    }
		}
	    }
	}
	unless (defined $cksum) {
	    die qq[$0: Failed to compute '$c' for "$f"\n];
	}
	my $t;
	($t = $f) =~ s/^.+\.tar/$label.tar/;
	emit("rm -f $t.$c.txt");
	emit("echo '$cksum  $f' > $t.$c.txt");
	emit_time_copy($f, "$t.$c.txt");
    }
}

for my $label (sort keys %Perl) {
    my ($dversion, $file, $lang, $major, $minor, $type, $age, $pretty) = 
	@{ $Perl{$label} };

    my @l = ($label);
    if ($label eq 'maint') {
	push @l, 'stable';
	push @l, 'latest';
    }

    for my $l (@l) {
	if ($l ne 'latest' && $dversion =~ /^\d/) {
	    emit("rm -f latest_${l}*");
	    emit("touch latest_${l}_is_$dversion");
	    emit_time_copy($file, "latest_${l}_is_$dversion");

	    emit("echo $dversion > latest_${l}");
	    emit_time_copy($file, "latest_${l}");
	}

	if ($l =~ /^[a-z]/) {
	    emit("rm -f ${l}_is_*");
	    emit("touch ${l}_is_$dversion");
	    emit_time_copy($file, "${l}_is_$dversion");
	}

	if (defined $file && $l =~ /^[a-z]/) {
	    my $rel = $file;
	    $rel =~ s|^CPAN/authors/|../authors/|;
	    emit("rm -f $l.tar.gz");
	    emit("ln -s $rel $l.tar.gz");
	    (my $bz2 = $rel) =~ s/\.gz$/.bz2/;
	    emit("rm -f $l.tar.bz2");
	    emit("test -f $bz2 && ln -s $bz2 $l.tar.bz2");
	    my ($vol, $d, $f) = File::Spec->splitpath($file);
	    emit_cksum($d, $f, $l);
	    if (-f $bz2) {
		emit_cksum($d, basename($bz2), $l);
	    }
	}
    }
}

exit(0);
