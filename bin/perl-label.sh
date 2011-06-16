#!/bin/sh -x

HOSTNAME=`hostname`

cd ~/cpan || exit 1

RELEASES=`mktemp /tmp/releases.XXXXXX`
LABEL=`mktemp /tmp/label.XXXXXX`
REPORT=`mktemp /tmp/report.XXXXXX`
README=`mktemp /tmp/readme.XXXXXX`

perl -w bin/perl-sorter.pl \
  --update_script=$LABEL \
  --latest_report=$REPORT | tee $RELEASES

if test ! -s $LABEL -o ! -s $REPORT -o ! -s $RELEASES
then
  echo 1>&2 "$0: $HOSTNAME: Something is wrong:"
  ls -l $LABEL $REPORT $RELEASES
  exit 1
fi

(cd CPAN/src && sh $LABEL)

perl bin/perl-report.pl $REPORT config/html/src/README.html > $README
if test -s $README
then
    if cmp -s $README CPAN/src/README.html
    then
      :
    else 
      chmod u-w,a+r $README
      mv -f $README CPAN/src/README.html
      chmod u-w,a+r CPAN/src/README.html
   fi
fi

rm -f $LABEL $REPORT $README $RELEASES

exit 0
