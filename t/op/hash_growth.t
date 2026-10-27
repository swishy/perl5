#!./perl
BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}
use strict;
use warnings;

# Cross several large-array growth boundaries, then delete and reinsert.
# Check visible behavior rather than an implementation-specific bucket count.
my %h;
$h{"key$_"} = $_ * 7 for 1..50000;
is(scalar(keys %h), 50000, 'all inserted keys survive hash growth');
my $bad = grep { !exists($h{"key$_"}) || $h{"key$_"} != $_ * 7 } 1..50000;
is($bad, 0, 'values preserved across growth');
delete $h{"key$_"} for grep { $_ % 3 == 0 } 1..50000;
is(scalar(keys %h), 50000 - int(50000 / 3), 'deletion after growth');
$h{"key$_"} = -$_ for grep { $_ % 3 == 0 } 1..50000;
$bad = grep { $h{"key$_"} != ($_ % 3 == 0 ? -$_ : $_ * 7) } 1..50000;
is($bad, 0, 'reinsertion preserves every value');
my %seen;
while (my ($key, $value) = each %h) { $seen{$key}++ }
is(scalar(keys %seen), 50000, 'iteration visits all keys');
is(scalar(grep { $_ != 1 } values %seen), 0, 'iteration visits each key once');
done_testing();
