#!/usr/bin/perl -w

use strict;

# perl-sorter.perl
#
# Scans the Perl releases - update the CPAN/src symlinks and meta files.
#
# $perl->{version} = 5.14.1-RC1
# $perl->{major} = 5;
# $perl->{minor} = 14;
# $perl->{iota} = 1;
#
# /src/ - symlink the STABLE versions:
# /src/<major.minor.iota>.tar.gz
# /src/<major.minor.iota>.tar.bz2
#
# /src/5.0/ - put the _full_ versions of everything here:
# /src/5.0/<major.minor.iota>.tar.gz[.md5.txt|.sha1.txt|.sha256.txt]
# /src/5.0/<major.minor.iota>.tar.bz2[.md5.txt|.sha1.txt|.sha256.txt]
# /indices/perl_version.json - all meta data (including sha1 and bz2)
#
# /src/stable.tar.gz
# /src/latest.tar.gz

use Carp qw/confess/;
use Getopt::Long;
use File::Slurp;
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

# Run once to clear out old files - check for others as well
#     "rm -f *.tar.* 5.0/*.tar.* 5.0/*/*.tar.*",
#     "rm -f *_is_* latest_* devel_* maint_* stable_*",
#     "rm -f 5.0/*_is_* 5.0/devel_* 5.0/maint_*",
#     "rm -f 5.0/devel 5.0/maint",

# check disk for files
foreach my $perl ( @{$perl_versions}, @{$perl_testing} ) {
    my $id = $perl->{cpanid};

    if ( $id =~ /^(.)(.)/ ) {
        my $path     = "CPAN/authors/id/$1/$1$2/$id";
        my $fileroot = "$path/" . $perl->{distvname};
        my @files    = glob("${fileroot}.*");

        die "Could not find perl ${fileroot}.*" unless scalar(@files);

        $perl->{files} = [];
        foreach my $file (@files) {
            my $meta = file_meta($fileroot);
            push( @{ $perl->{files} }, $meta );
        }
    }
}

# Create file / symlinks for ALL versions in /src/5.0/
# src/5.0/perl-5.12.4-RC1.tar.bz2
# src/5.0/perl-5.12.4-RC1.tar.bz2.md5.txt
# src/5.0/perl-5.12.4-RC1.tar.bz2.sha1.txt
# src/5.0/perl-5.12.4-RC1.tar.bz2.sha256.txt
# src/5.0/perl-5.12.4-RC1.tar.gz
# src/5.0/perl-5.12.4-RC1.tar.gz.md5.txt
# src/5.0/perl-5.12.4-RC1.tar.gz.sha1.txt
# src/5.0/perl-5.12.4-RC1.tar.gz.sha256.txt

# Old format for md5 sha1 sha256 was:
# 8d8bf968439fcf4a0965c335d1ccd981  5.0/perl-5.14.1-RC1.tar.gz
# Now just putting the secrity data as think the 5.0/ was a bug?
# 8d8bf968439fcf4a0965c335d1ccd981

foreach my $perl ( ( @{$perl_versions}, @{$perl_testing} ) ) {

    # For a perl e.g. perl-5.12.4-RC1
    # create or symlink:
    foreach my $file ( @{ $perl->{files} } ) {

        my $out   = "src/5.0/" . $file->{file};

        foreach my $security (qw(md5 sha1 sha256)) {

            print_file_if_different( "${out}.${security}.txt",
                $file->{$security} );
        }
        create_symlink( $file->{filepath}, $out );

		# only link stable versions directly from src/
		next unless $perl->{status} eq 'stable';
        my $out_src = "src/" . $file->{file};
        create_symlink( $file->{filepath}, '../' .$out );

    }
}


sub print_file_if_different {
    my ( $file, $data ) = @_;

    if ( -r $file ) {
        my $content = read_file($file);
        return if $content eq $data;
    }

    open my $fh, ">:utf8", "$file"
        or die "Could not open data/$file: $!";
    print $fh $data;
    close $fh;

}

#
#
# my $fn = 'out_file.sh';
# my @Perl;
# if ( open( my $fh, ">", $fn ) ) {
#     select $fh;
#
#     for my $p (@Perl) {
#         my ( $file, $lang, $major, $minor, $iota, $type, $mtime, $md5, $sha1,
#             $sha256, $latest, $obsoleted, $latest_of_type, $ago )
#             = @$p;
#         printf qq[: "%s"\n], join( ":", @$p );
#         my %info = (
#             mtime  => $mtime,
#             md5    => $md5,
#             sha1   => $sha1,
#             sha256 => $sha256
#         );
#         emit_symlink( $file, \%info, "5.0" );
#         if ( $latest ne "-" ) {
#             if ( $obsoleted eq "-" ) {
#                 emit_symlink( $file, \%info );
#                 if ( $latest_of_type ne "-" ) {
#                     my $release = "$lang.$major.$minor";
#                     emit_symlink_typed( $file, $type, \%info );
#                     emit_symlink_typed( $file, $type, \%info, "5.0" );
#                     if ( $type eq "maint" || $type eq "devel" ) {
#                         emit_symlink( $file, \%info, "5.0/$type" );
#                         emit_symlink_typed( $file, $type, \%info,
#                             "5.0/$type" );
#                     }
#                     if ( $type eq "maint" ) {
#                         for my $l (qw(stable latest)) {
#                             emit_symlink_typed( $file, $l, \%info );
#                         }
#                     }
#                     my $t0 = "latest_${latest}_is_$release";
#                     my $t1 = "latest_${type}_is_$release";
#                     my $t2 = "${type}_is_$release";
#                     emit_touch( $t0, \%info );
#                     emit_touch( $t1, \%info );
#                     emit_touch( $t2, \%info );
#                     if ( $type eq "maint" || $type eq "devel" ) {
#
#                         for my $t ( $t0, $t1, $t2 ) {
#                             emit_touch( "5.0/$t",       \%info );
#                             emit_touch( "5.0/$type/$t", \%info );
#                         }
#                     }
#                     my $t3 = "latest_${latest}";
#                     my $t4 = "latest_${type}";
#                     emit_echo( $release, $t3, \%info );
#                     emit_echo( $release, $t4, \%info );
#                     if ( $type eq "maint" || $type eq "devel" ) {
#                         for my $t ( $t3, $t4 ) {
#                             emit_echo( $release, "5.0/$t",       \%info );
#                             emit_echo( $release, "5.0/$type/$t", \%info );
#                         }
#                     }
#                 }
#             }
#         }
#     }
#     print "exit 0\n";
#     select STDOUT;
# } else {
#     die qq[$0: Failed to create "$fn": $!];
# }
#
# exit(0);

#### NEW CLEANER CODE....

=head2 create_symlink

    create_symlink($oldfile, $newfile);

Will remove $newfile if it already exists and then create
the symlink.

=cut

sub create_symlink {
    my ( $oldfile, $newfile ) = @_;
    die "Could not read: $oldfile" unless -r $oldfile;

    # Clean out old links
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
    my $file     = shift;
    my $filename = basename($file);
    my $dir      = dirname($file);
    my $checksum = "$dir/CHECKSUMS";

    # The CHECKSUM file has already calculated
    # lots of this so use that
    my $cksum;
    unless ( defined( $cksum = do $checksum ) ) {
        die qq[Checksums file "$checksum" not found\n];
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
        file     => $file,
        filedir  => $dir,
        filename => $filename,
        mtime    => ( stat($file) )[9],
        md5      => $cksum->{$filename}->{md5},
        sha256   => $cksum->{$filename}->{sha256},
        sha1     => $sha1,
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
