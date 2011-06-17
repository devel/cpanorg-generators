#!/bin/sh -x

cd ~/cpan || exit 1

# search.cpan.org + perl-sorter and the new TT content system now does
# all the work previously done by perl-label.pl and the old perl-sorter.pl.

perl -w bin/perl-sorter.pl

exit 0
