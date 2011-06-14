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
use File::Basename qw/dirname basename/;

use JSON ();
use LWP::Simple qw(get);

# If debug set then shell commands are just printed and not run
my $DEBUG = 1;

my $json = JSON->new->pretty;

# check directories exist
foreach my $dir ( '../src', '../cpla', '../../CPAN/src' ) {
    die "$dir does not exist, are you running from the right dir?"
        unless -d $dir;
}

my ( $perl_versions, $perl_testing ) = fetch_perl_version_data();

# check disk for files
for my $perl ( @{$perl_versions}, @{$perl_testing} ) {
    my $id = $perl->{cpanid};

    if ( $id =~ /^(.)(.)/ ) {
        my $path     = "CPAN/authors/id/$1/$1$2/$id";
        my $fileroot = "$path/" . $perl->{distvname};
        my @files    = glob("${fileroot}.*");

        die "Could not find perl ${fileroot}.*" unless scalar(@files);

        $perl->{files} = \@files;
    }
}

# Clear out all old content:
# As the script now removes symlinks before creating new
# this might not be needed?
#for my $c (qw(md5 sha1 sha256)) {
#    my $cmd = "rm -f *.$c.txt 5.0/*.$c.txt 5.0/*/*.$c.txt";
#    run_cmd($cmd);
#}

foreach my $cmd (
    "rm -f *.tar.* 5.0/*.tar.* 5.0/*/*.tar.*",
    "rm -f *_is_* latest_* devel_* maint_* stable_*",
    "rm -f 5.0/*_is_* 5.0/devel_* 5.0/maint_*",
    "rm -f 5.0/devel/*_is_* 5.0/maint/*_is_*",
    )
{
    run_cmd($cmd);
}


{
    # Contents of these files is a version number e.g. 5.13.11
    

    # create 5.0/latest_<major.minor version> e.g. latest_5.14

    # create 5.0/latest_devel
    
    # create 5.0/latest_maint


    # create 5.0/maint/latest_<major.minor
    
    # create 5.0/perl<major.minor.iota...>.tar.gz
    # and the .md5.txt, sha1.txt, sha256.txt textfiles
    # for every perl 5 version (including RC's)
    
    
}






sub emit_unlink {
    my ($file) = @_;
    print "rm -f $file\n";
}

my %echoed;

sub emit_echo {
    my ( $echo, $file, $info ) = @_;
    unless ( $echoed{$file}++ ) {
        print qq[echo '$echo' > $file\n];
        emit_utime( $info, $file );
    }
}

my %utimed;

sub emit_utime {
    my ( $info, @file ) = @_;
    @file = grep { !$utimed{$_}++ } @file;
    if (@file) {
        my $mtime = $info->{mtime};
        confess(qq[bad mtime]) unless defined $mtime;
        print qq[perl -e 'utime $mtime, $mtime, \@ARGV' @file\n];
    }
}

sub emit_cksum {
    my ( $basename, $info ) = @_;
    for my $c (qw(md5 sha1 sha256)) {
        emit_echo( "$info->{$c}  $basename", "$basename.$c.txt", $info );
        emit_utime( $info, $basename );
    }
}

sub emit_symlink {
    my ( $file, $info, $more ) = @_;
    my $without_top = $file;
    $without_top =~ s|^(.+?/)||;
    my $basename   = basename($file);
    my $dotdotpath = "..";
    if ( defined $more ) {
        $dotdotpath = "../" x ( 1 + $more =~ tr:/:/: ) . $dotdotpath;
    }
    my $path = defined $more ? "$more/$basename" : $basename;
    emit_unlink($path);
    print "ln -s $dotdotpath/$without_top $path\n";
    emit_cksum( $path, $info );
}

sub emit_symlink_typed {
    my ( $file, $label, $info, $more ) = @_;
    my $without_top = $file;
    $without_top =~ s|^(.+?/)||;
    my $dotdotpath = "..";
    if ( defined $more ) {
        $dotdotpath = "../" x ( 1 + $more =~ tr:/:/: ) . $dotdotpath;
    }
    my ($suffix) = ( $file =~ m|(\.tar\..+)$| );
    my $l = "$label$suffix";
    $l = "$more/$l" if defined $more;
    emit_unlink($l);
    print "ln -s $dotdotpath/$without_top $l\n";
    emit_cksum( $l, $info );
}

my %touched;

sub emit_touch {
    my ( $file, $info ) = @_;
    unless ( $touched{$file}++ ) {
        print "touch $file\n";
        emit_utime( $info, $file );
    }
}

if ( defined $Options{update_script} ) {
    my $fn = $Options{update_script};

    if ( open( my $fh, ">", $fn ) ) {
        select $fh;

        for my $p (@Perl) {
            my ( $file, $lang, $major, $minor, $iota, $type, $mtime, $md5,
                $sha1, $sha256, $latest, $obsoleted, $latest_of_type, $ago )
                = @$p;
            printf qq[: "%s"\n], join( ":", @$p );
            my %info = (
                mtime  => $mtime,
                md5    => $md5,
                sha1   => $sha1,
                sha256 => $sha256
            );
            emit_symlink( $file, \%info, "5.0" );
            if ( $latest ne "-" ) {
                if ( $obsoleted eq "-" ) {
                    emit_symlink( $file, \%info );
                    if ( $latest_of_type ne "-" ) {
                        my $release = "$lang.$major.$minor";
                        emit_symlink_typed( $file, $type, \%info );
                        emit_symlink_typed( $file, $type, \%info, "5.0" );
                        if ( $type eq "maint" || $type eq "devel" ) {
                            emit_symlink( $file, \%info, "5.0/$type" );
                            emit_symlink_typed( $file, $type, \%info,
                                "5.0/$type" );
                        }
                        if ( $type eq "maint" ) {
                            for my $l (qw(stable latest)) {
                                emit_symlink_typed( $file, $l, \%info );
                            }
                        }
                        my $t0 = "latest_${latest}_is_$release";
                        my $t1 = "latest_${type}_is_$release";
                        my $t2 = "${type}_is_$release";
                        emit_touch( $t0, \%info );
                        emit_touch( $t1, \%info );
                        emit_touch( $t2, \%info );
                        if ( $type eq "maint" || $type eq "devel" ) {

                            for my $t ( $t0, $t1, $t2 ) {
                                emit_touch( "5.0/$t",       \%info );
                                emit_touch( "5.0/$type/$t", \%info );
                            }
                        }
                        my $t3 = "latest_${latest}";
                        my $t4 = "latest_${type}";
                        emit_echo( $release, $t3, \%info );
                        emit_echo( $release, $t4, \%info );
                        if ( $type eq "maint" || $type eq "devel" ) {
                            for my $t ( $t3, $t4 ) {
                                emit_echo( $release, "5.0/$t",       \%info );
                                emit_echo( $release, "5.0/$type/$t", \%info );
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

exit(0);

#### NEW CLEANER CODE....

=head2 create_symlink

    create_symlink($oldfile, $newfile);

Will remove $newfile if it already exists and then create
the symlink.

=cut

sub create_symlink {
    my ( $oldfile, $newfile ) = @_;
    die "Could not read: $oldfile" unless -r $oldfile;
    unlink($newfile) if -r $newfile;
    symlink( $oldfile, $newfile );
}

sub run_cmd {
    my $cmd = shift;
    if ($DEBUG) {
        print "Running: $cmd\n";
    } else {
        system($cmd) unless $DEBUG;
    }
}

=head2 file_meta
    
    my $meta = file_meta($file);

    print $meta->{md5};
    print $meta->{sha256};
    print $meta->{mtime};
    print $meta->{sha1};

Get or calculate meta information about a file

=cut

sub file_meta {
    my $file = shift;
    my $f    = basename($file);
    my $d    = dirname($file);
    my $c    = "$d/CHECKSUMS";

    # The CHECKSUM file has already calculated
    # lots of this so use that
    my $cksum;
    unless ( defined( $cksum = do $c ) ) {
        die qq[Checksums file "$c" not found\n];
    }

    # Calculate the sha1
    my $sha1;
    if ( open( my $fh, "openssl sha1 $file |" ) ) {
        while (<$fh>) {
            if (/^SHA1\(.+?\)= ([0-9a-f]+)$/) {
                $sha1 = $1;
                last;
            }
        }
    }
    die qq[Failed to compute sha1 for $file\n] unless defined $sha1;

    return {
        mtime  => ( stat($file) )[9],
        md5    => $cksum->{$f}->{md5},
        sha256 => $cksum->{$f}->{sha256},
        sha1   => $sha1,
    };
}

#### THE CODE BELOW HERE IS FROM:
# https://github.com/perlorg/cpanorg/blob/master/bin/cpanorg_perl_releases
# Maybe make it into a module or something?
sub sort_versions {
    my $list = shift;

    my @sorted = sort {
               $b->{version_major} <=> $a->{version_major}
            || int( $b->{version_minor} ) <=> int( $a->{version_minor} )
            || $b->{version_iota} <=> $a->{version_iota}
    } @{$list};

    return \@sorted;

}

sub extract_first_per_version_in_list {
    my $versions = shift;

    my $lookup = {};
    foreach my $version ( @{$versions} ) {
        my $minor_version = $version->{version_major} . '.'
            . int( $version->{version_minor} );

        $lookup->{$minor_version} = $version
            unless $lookup->{$minor_version};
    }
    return $lookup;
}

sub fetch_perl_version_data {
    my $perl_dist_url = "http://search.cpan.org/api/dist/perl";

    my $filename = 'perl_version_all.json';

    # See what we have on disk
    my $disk_json = '';
    $disk_json = read_file("data/$filename")
        if -r "data/$filename";

    my $cpan_json = get($perl_dist_url);
    die "Unable to fetch $perl_dist_url" unless $cpan_json;

    if ( $cpan_json eq $disk_json ) {

        # Data has not changed so don't need to do anything
        exit;
    } else {

        # Save for next fetch
        print_file( $filename, $cpan_json );
    }

    my $data = $json->decode($cpan_json);

    my @perls;
    my @testing;
    foreach my $module ( @{ $data->{releases} } ) {
        next unless $module->{authorized} eq 'true';

        my $version = $module->{version};

        $version =~ s/-(?:RC|TRIAL)\d+$//;
        $module->{version_number} = $version;

        my ( $major, $minor, $iota ) = split( '[\._]', $version );
        $module->{version_major} = $major;
        $module->{version_minor} = int($minor);
        $module->{version_iota}  = int( $iota || '0' );

        $module->{type}
            = $module->{status} eq 'testing'
            ? 'Devel'
            : 'Maint';

        # TODO: Ask - please add some validation logic here
        # so that on live it checks this exists
        my $zip_file = $module->{distvname} . '.tar.gz';

        $module->{zip_file} = $zip_file;
        $module->{url} = "http://www.cpan.org/src/" . $module->{zip_file};

        ( $module->{released_date}, $module->{released_time} )
            = split( 'T', $module->{released} );

        next if $major < 5;

        if ( $module->{status} eq 'stable' ) {
            push @perls, $module;
        } else {
            push @testing, $module;
        }
    }
    return \@perls, \@testing;
}
