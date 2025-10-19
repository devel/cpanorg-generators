#!/usr/bin/perl -w

use strict;

# Script written by Leo Lapworth

# Run once to clear out old files - in /src/
# rm -f *.tar.* 5.0/*.tar.* 5.0/*/*.tar.*
# rm -f *_is_* latest_* devel_* maint_* stable_*
# rm -f 5.0/*_is_* 5.0/devel_* 5.0/maint_* 5.0/latest*
# rm -rf 5.0/devel 5.0/maint

# perl-sorter.perl
#
# Scans the Perl releases - update the CPAN/src symlinks and meta files.
#
# $perl->{version} = 5.14.1-RC1
# $perl->{major} = 5;
# $perl->{minor} = 14;
# $perl->{iota} = 1;
#
# Files to manage (either symlink or create)
#
# /src/ - symlink all STABLE versions:
# /src/<major.minor.iota>.tar.gz
# /src/<major.minor.iota>.tar.bz2
# /src/<major.minor.iota>.tar.xz
#
# /src/5.0/ - symlink all versions + security files:
# /src/5.0/<major.minor.iota>-RC.tar.gz[.md5.txt|.sha1.txt|.sha256.txt]
# /src/5.0/<major.minor.iota>.tar.bz2[.md5.txt|.sha1.txt|.sha256.txt]
# /indices/perl_version.json - all meta data (including sha1 and bz2)
#
# /src/stable.tar.gz
# /src/latest.tar.gz (what's this actually mean?)

use Carp qw/confess/;
use File::Basename qw/dirname basename/;
use File::Slurp 9999.19;
use Getopt::Long;
use JSON ();
use LWP::Simple qw(get);

# Where the CPAN folder is
my $CPAN = $ENV{CPAN} || 'CPAN';

# Working directory for data cache
my $WORKDIR = $ENV{WORKDIR} || '.';

# check directories exist
foreach my $dir ( "$CPAN/src", "$CPAN/authors" ) {
    die "$dir does not exist, are you running from the right dir?"
        unless -d $dir;
}

# make a directory to cache data ( for fetch_perl_version_data() )
my $data_dir = "$WORKDIR/data";
mkdir($data_dir) unless -d $data_dir;

my $json = JSON->new->pretty(1);

my ( $perl_versions, $perl_testing ) = fetch_perl_version_data();

chdir($CPAN);

# check disk for files
foreach my $perl ( @{$perl_versions}, @{$perl_testing} ) {
    my $id = $perl->{cpanid};

    if ( $id =~ /^(.)(.)/ ) {
        my $path     = "authors/id/$1/$1$2/$id";
        my $fileroot = "$path/" . $perl->{distvname};
        my @files    = glob("${fileroot}.*tar.*");

        die "Could not find perl ${fileroot}.*" unless scalar(@files) or $fileroot =~ m/RC/;

        $perl->{files} = [];
        foreach my $file (@files) {
            my $meta = file_meta($file);
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

# just to make it easier for testing
my $src = "src";

foreach my $perl ( ( @{$perl_versions}, @{$perl_testing} ) ) {

    # For a perl e.g. perl-5.12.4-RC1
    # create or symlink:
    foreach my $file ( @{ $perl->{files} } ) {

        my $filename = $file->{file};

        my $out = "${src}/5.0/" . $file->{filename};

        foreach my $security (qw(md5 sha1 sha256)) {

            print_file_if_different( "${out}.${security}.txt",
                $file->{$security} );
        }

        create_symlink( ( ( '../' x 2 ) . $file->{file} ), $out );

        # only link stable versions directly from src/
        next unless $perl->{status} eq 'stable';
        create_symlink(
            ( ( '../' x 1 ) . $file->{file} ),
            "${src}/" . $file->{filename}
        );

    }
}

# Latest only symlinks
# /src/latest.tar....
# /src/stable.tar....
{
    my $latest_per_version
        = extract_first_per_version_in_list($perl_versions);

    my $latest = sort_versions( [ values %{$latest_per_version} ] )->[0];

    foreach my $file ( @{ $latest->{files} } ) {

        for my $type (qw(latest stable)) {
            my ($ext) = ($file->{file} =~ m/(bz2|gz|xz)$/) or next;
            my $out = "${src}/${type}.tar.${ext}";
            warn "creating symlink for ", $file->{file}, " to $out";
            create_symlink('../' . $file->{file}, $out);
        }
    }

}

sub print_file_if_different {
    my ( $file, $data ) = @_;

    if ( -r $file ) {
        my $content = read_file($file);
        return if $content eq $data;
    }

    write_file( "$file", { binmode => ':utf8' }, $data )
        or die "Could not open $file: $!";
}

=head2 create_symlink

    create_symlink($oldfile, $newfile);

Will unlink $newfile if it already exists and then create
the symlink.

=cut

sub create_symlink {
    my ( $oldfile, $newfile ) = @_;

    # Clean out old symlink if it does not point to correct location
    if ( -l $newfile && readlink($newfile) ne $oldfile ) {
        unlink($newfile);
    }
    symlink( $oldfile, $newfile ) unless -l $newfile;
}

=head2 file_meta
    
    my $meta = file_meta($file);

	print $meta->{file};
	print $meta->{filename};
	print $meta->{filedir};
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

#### THE CODE BELOW HERE IS COPIED FROM:
# https://github.com/perlorg/cpanorg/blob/master/bin/cpanorg_perl_releases
# Maybe make it into a module or something?
sub print_file {
    my ( $file, $data ) = @_;

    write_file( "$data_dir/$file", { binmode => ':utf8' }, $data )
        or die "Could not open $data_dir/$file: $!";
}

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
    my $perl_dist_url = "http://search.mcpan.org/api/dist/perl";

    my $filename = 'perl_version_all.json';

    # See what we have on disk
    my $disk_json = '';
    $disk_json = read_file("$data_dir/$filename")
        if -r "$data_dir/$filename";

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
        $module->{url} = "http://www.cpan.org/src/5.0/" . $module->{zip_file};

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

