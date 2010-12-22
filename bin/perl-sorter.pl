#!/usr/bin/perl -w

#
# perl-sorter.perl
#
# Scans the Perl releases, sorts them, and optionally generates
# shell script to update the CPAN/src symlinks and label files.
#

use strict;

use Carp qw/confess/;
use Getopt::Long;

sub usage {
    die <<__EOF__;
$0: Usage:
$0 [--update_script=script.sh] [--latest_report=latest.txt]
__EOF__
}

my %Options;

usage() unless GetOptions('update_script=s' =>
			  \$Options{update_script},
			  'latest_report=s' =>
			  \$Options{latest_report});

use File::Basename qw/dirname basename/;

my @Pumpkin5;

my $Pumpkin5 = "http://pause.perl.org/pause/query?ACTION=who_pumpkin;OF=YAML";

$ENV{PATH} = "/usr/local/bin:$ENV{PATH}";  # For curl.
$ENV{PATH} = "/opt/csw/bin:$ENV{PATH}";  # For openssl.
$ENV{PATH} = "/opt/sfw/bin:$ENV{PATH}";  # For openssl.

if (open(my $fh, "curl -s '$Pumpkin5'|")) {
    while (<$fh>) {
	if (/^- ([\w-]+)$/) {
	    push @Pumpkin5, $1;
	}
    }
}

die qq[$0: No Perl5 pumpkins found\n] unless @Pumpkin5;

my @Perl;

for my $id (@Pumpkin5) {
    if ($id =~ /^(.)(.)/) {
	my $path = "CPAN/authors/id/$1/$1$2/$id";
	my @glob;
	push @glob, glob("$path/perl-5.*.tar.*");
	push @glob, glob("$path/perl5.*.tar.*");
	push @Perl, @glob;
    }
}

@Perl = grep { ! /-bindist\d/ } @Perl;

sub perl_version_extractor {
    my $perl = shift;
    if ($perl =~ /perl-5\.(\d+)\.(\d+)(?:-(?:RC|TRIAL)(\d+))?\.tar\.(?:gz|bz2)$/) {
	return (5, $1, $2, defined $3 ? $3 + 1 : 0);
    } elsif ($perl =~ /perl5\.0*(\d+)(?:_0*(\d+))?(?:-(?:RC|TRIAL)(\d+))?\.tar\.(?:gz|bz2)$/) {
	return (5, $1, $2 || 0, defined $3 ? $3 + 1 : 0);
    }
}

sub perl_version_classifier {
    my $perl = shift;
    my ($lang, $major, $minor, $iota) = perl_version_extractor($perl);
    my $type =
#	$minor == 0 && $major % 2 == 0 || $iota > 0 ? 'testing' :
	$iota > 0 ? 'testing' :
	    $major < 6 ? 'maint' : $major % 2 == 0 ? 'maint' : 'devel';
    return ($lang, $major, $minor, $iota, $type);
}

sub perl_file_info {
    my $file = $_;
    my $mtime = (stat($file))[9];
    my $f = basename($file);
    my $d = dirname($file);
    my $c = "$d/CHECKSUMS";
    my $cksum;
    unless (defined($cksum = do $c)) {
	die qq[Checksums file "$c" not found\n];
    }
    my $md5 = $cksum->{$f}->{md5};
    my $sha256 = $cksum->{$f}->{sha256};
    my $sha1;
    if (open(my $fh, "openssl sha1 $file |")) {
	while (<$fh>) {
	    if (/^SHA1\(.+?\)= ([0-9a-f]+)$/) {
		$sha1 = $1;
		last;
	    }
	}
    }
    unless (defined $sha1) {
	die qq[Failed to compute sha1 for $file\n];
    }
    return ($mtime, $md5, $sha1, $sha256);
}

#
# Classify the versions, add file information.
#

@Perl = map { my $f = $_;
	      [ 
	       $f,
	       perl_version_classifier($f),
	       perl_file_info($f),
	      ] } @Perl;

#
# Sort by the versions.
#

@Perl = sort { $a->[1] <=> $b->[1] ||
	       $a->[2] <=> $b->[2] ||
	       $a->[3] <=> $b->[3] ||
	       $a->[4] <=> $b->[4]} @Perl; 

my %Perl;
my %ByType;

for my $p (@Perl) {
    my ($file, $lang, $major, $minor, $iota, $type) = @$p;
    $Perl{$lang}{$major}{$minor}{$file}++;
}

#
# Compute "latest".
#

my %Latest;

for my $lang (sort { $a <=> $b } keys %Perl) {
    my @major = sort { $a <=> $b } keys %{ $Perl{$lang} };
    for my $major (@major) {
	my @minor = sort { $a <=> $b } keys %{ $Perl{$lang}{$major} };
	my $minor = $minor[-1];
	for my $file (keys %{ $Perl{$lang}{$major}{$minor} }) { 
	    $Latest{$lang}{$major}{$minor}{$file}++;
	}
    }
}

#
# Add "latest" and "obsoleted by" columns.
# 

for my $p (@Perl) {
    my ($file, $lang, $major, $minor, $iota, $type) = @$p;
    # "latest in line"
    push @$p,
         $Latest{$lang}{$major}{$minor}{$file} ?
           "$lang.$major" : "-";
    push @{ $ByType{ $type } }, "$lang.$major.$minor";
    # "obsoleted by"
    my $next = $major + 1;
    push @$p,
         $type eq 'devel' && exists $Latest{$lang}{$next} ?
           "$lang.$next" : $type eq 'testing' ? "$lang.$major.$minor" :"-";
}

#
# Add "latest of type" column.
#

for my $p (@Perl) {
    my ($file, $lang, $major, $minor, $iota, $type) = @$p;
    push @$p, $ByType{$type}[-1] eq "$lang.$major.$minor" ? $type : "-";
}

#
# Add human-friendly age column: "1 year, 7 months".
#

my $Now = time();

sub ago {
    my $ago = shift;
    my $days = int($ago / 86400);
    my @ago;
    if ($days < 1) {
	@ago = 'today';
    } else {
	my $tmp = $days;
	my $kyear = 365.2425;
	my $years = int($tmp / $kyear);
	if ($years) {
	    push @ago,
	      sprintf "%d year%s", $years, $years == 1 ? '' : 's';
	    $tmp -= int($years * $kyear);
	} 
	my $kmonth = 30.436875;
	my $months = int($tmp / $kmonth);
	if ($months) {
	    push @ago,
	      sprintf "%d month%s", $months, $months == 1 ? '' : 's';
	    $tmp -= $months * $kmonth;
	}
	my $days = int($tmp);
	if ($days) {
	    push @ago, sprintf "%d day%s", $days, $days == 1 ? '' : 's';
	    $tmp -= $days;
	}
	my $hours = int($tmp * 24);
	if ($hours) {
	    push @ago, 
	    sprintf "%d hour%s", $hours, $hours == 1 ? '' : 's';
	}
    }

    splice @ago, 2 if @ago > 2;  # At most two items is enough.
    return @ago;  
}

for my $p (@Perl) {
    my ($file, $lang, $major, $minor, $iota, $type, $mtime) = @$p;
    push @$p, join(", ", ago($Now - $mtime));
}

for my $p (@Perl) {
    print join(":", @$p), "\n";
}

sub emit_unlink {
    my ($file) = @_;
    print "rm -f $file\n";
}

my %echoed;

sub emit_echo {
    my ($echo, $file, $info) = @_;
    unless ($echoed{$file}++) {
	print qq[echo '$echo' > $file\n];
	emit_utime($info, $file);
    }
}

my %utimed;

sub emit_utime {
    my ($info, @file) = @_;
    @file = grep { !$utimed{$_}++ } @file;
    if (@file) {
	my $mtime = $info->{mtime};
	confess(qq[bad mtime]) unless defined $mtime;
	print qq[perl -e 'utime $mtime, $mtime, \@ARGV' @file\n];
    }
}

sub emit_cksum {
    my ($basename, $info) = @_;
    for my $c (qw(md5 sha1 sha256)) {
	emit_echo("$info->{$c}  $basename", "$basename.$c.txt", $info);
	emit_utime($info, $basename);
    }
}

sub emit_symlink {
    my ($file, $info, $more) = @_;
    my $without_top = $file;
    $without_top =~ s|^(.+?/)||;
    my $basename = basename($file);
    my $dotdotpath = "..";
    if (defined $more) {
	$dotdotpath = "../" x (1 + $more =~ tr:/:/:) . $dotdotpath;
    }
    my $path = defined $more ? "$more/$basename" : $basename;
    emit_unlink($path);
    print "ln -s $dotdotpath/$without_top $path\n";
    emit_cksum($path, $info);
}

sub emit_symlink_typed {
    my ($file, $label, $info, $more) = @_;
    my $without_top = $file;
    $without_top =~ s|^(.+?/)||;
    my $dotdotpath = "..";
    if (defined $more) {
	$dotdotpath = "../" x (1 + $more =~ tr:/:/:) . $dotdotpath;
    }
    my ($suffix) = ($file =~ m|(\.tar\..+)$|);
    my $l = "$label$suffix";
    $l = "$more/$l" if defined $more;
    emit_unlink($l);
    print "ln -s $dotdotpath/$without_top $l\n";
    emit_cksum($l, $info);
}

my %touched;

sub emit_touch {
    my ($file, $info) = @_;
    unless ($touched{$file}++) {
	print "touch $file\n";
	emit_utime($info, $file);
    }
}

if (defined $Options{update_script}) {
    my $fn = $Options{update_script};
    if (open(my $fh, ">", $fn)) {
	select $fh;
	print "test -d ../src         || exit 1\n";
	print "test -d ../clpa        || exit 1\n";
	print "test -d ../../CPAN/src || exit 1\n";
	for my $c (qw(md5 sha1 sha256)) {
	    print "rm -f *.$c.txt 5.0/*.$c.txt 5.0/*/*.$c.txt\n";
	}
	print "rm -f *.tar.* 5.0/*.tar.* 5.0/*/*.tar.*\n";
	print "rm -f *_is_* latest_* devel_* maint_* stable_*\n";
	print "rm -f 5.0/*_is_* 5.0/devel_* 5.0/maint_*\n";
	print "rm -f 5.0/devel/*_is_* 5.0/maint/*_is_*\n";
	for my $p (@Perl) {
	    my ($file, $lang, $major, $minor, $iota, $type,
		$mtime, $md5, $sha1, $sha256,
		$latest, $obsoleted, $latest_of_type, $ago) = @$p;
	    printf qq[: "%s"\n], join(":", @$p);
	    my %info = (mtime  => $mtime,
			md5    => $md5,
			sha1   => $sha1,
			sha256 => $sha256);
	    emit_symlink($file, \%info, "5.0");
	    if ($latest ne "-") {
		if ($obsoleted eq "-") {
		    emit_symlink($file, \%info);
		    if ($latest_of_type ne "-") {
			my $release = "$lang.$major.$minor";
			emit_symlink_typed($file, $type, \%info);
			emit_symlink_typed($file, $type, \%info, "5.0");
			if ($type eq "maint" || $type eq "devel") {
			    emit_symlink($file, \%info, "5.0/$type");
			    emit_symlink_typed($file, $type, \%info,
					       "5.0/$type");
			}
			if ($type eq "maint") {
			    for my $l (qw(stable latest)) {
				emit_symlink_typed($file, $l, \%info);
			    }
			}
			my $t0 = "latest_${latest}_is_$release";
			my $t1 = "latest_${type}_is_$release";
			my $t2 = "${type}_is_$release";
			emit_touch($t0, \%info);
			emit_touch($t1, \%info);
			emit_touch($t2, \%info);
			if ($type eq "maint" || $type eq "devel") {
			    for my $t ($t0, $t1, $t2) {
				emit_touch("5.0/$t", \%info);
				emit_touch("5.0/$type/$t", \%info);
			    }
			}
			my $t3 = "latest_${latest}";
			my $t4 = "latest_${type}";
			emit_echo($release, $t3, \%info);
			emit_echo($release, $t4, \%info);
			if ($type eq "maint" || $type eq "devel") {
			    for my $t ($t3, $t4) {
				emit_echo($release, "5.0/$t", \%info);
				emit_echo($release, "5.0/$type/$t", \%info);
			    }
			}
		    }
		}
	    }
	}
	print "exit 0\n";
	select STDOUT;
    } else {
	die qq[$0: Failed to create "$fn": $!];
    }
}

my %LatestOfBranch;
my @LatestOfBranch;

if (defined $Options{latest_report}) {
    my $fn = $Options{latest_report};
    if (open(my $fh, ">", $fn)) {
	for my $p (reverse @Perl) {
	    my ($file, $lang, $major, $minor, $iota, $type,
		$mtime, $md5, $sha1, $sha256,
		$latest, $obsoleted, $latest_of_type, $ago) = @$p;
	    if ($latest ne "-" && $obsoleted eq "-") {
		my $branch = "$lang.$major";
		unless (exists $LatestOfBranch{$branch}) {
		    push @LatestOfBranch, $branch;
		}
		push @{ $LatestOfBranch{$branch}{file} }, $file;
		$LatestOfBranch{$branch}{info} =
		    [ "$branch.$minor", $type, $ago ];
	    }
	}
	for my $branch (@LatestOfBranch) {
	    my $file = join(",",
			    @{ $LatestOfBranch{$branch}{file} });
	    my ($release, $type, $ago) =
		@{ $LatestOfBranch{$branch}{info} };
	    print $fh join(":", $branch, $release,
			   $file, $type, $ago), "\n";
	}
	close($fh);
    } else {
	die qq[$0: Failed to create "$fn": $!];
    }
}

exit(0);
