#!./perl
BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
}
use strict;
use warnings;
use Scalar::Util qw(dualvar);

# The indirect comparator forces the generic path, providing an independent
# language-level result for the recognized built-in numeric sorts.
my $cmp = sub { $_[0] <=> $_[1] };
my @cases = (
    ['signed', [map { 50 - $_ } 1..100]],
    ['fractional', [map { (50 - $_) / 7 } 1..100]],
    ['mixed', [map { $_ % 3 ? $_ / 7 : -$_ } reverse 1..100]],
    ['unsigned', [map { (~0 >> 1) + $_ } reverse 1..100]],
    ['precision boundary', [map { $_ % 3 ? (1 << 62) + $_ : ((1 << 62) + $_) * 1.0 } 1..100]],
    ['references', [map { [$_] } 1..40]],
    ['numeric strings', [map { "$_" } reverse 1..100]],
    ['stable ties', [map { dualvar($_ % 4, "item$_") } 1..100]],
    ['signed zero', [(-0.0, 0.0, -1.0, 1.0) x 25]],
);
for my $case (@cases) {
    my ($name, $values) = @$case;
    my @want = sort { $cmp->($a, $b) } @$values;
    my @got = sort { $a <=> $b } @$values;
    is(join('|', @got), join('|', @want), "$name ascending and stable ties");
    @want = sort { $cmp->($b, $a) } @$values;
    @got = sort { $b <=> $a } @$values;
    is(join('|', @got), join('|', @want), "$name descending");
    my @inplace = @$values;
    @inplace = sort { $b <=> $a } @inplace;
    is(join('|', @inplace), join('|', @want), "$name in-place");
}
for my $n (0, 1, 2, 15, 16, 17, 31, 32, 33, 127) {
    my @values = reverse 1..$n;
    my @got = sort { $a <=> $b } @values;
    is(join('|', @got), join('|', 1..$n), "numeric sort length $n");
}
my @integer_values = map { ($_ - 50) / 3 } reverse 1..100;
{
    use integer;
    my $integer_cmp = sub { $_[0] <=> $_[1] };
    my @values = @integer_values;
    my @want = sort { $integer_cmp->($a, $b) } @values;
    my @got = sort { $a <=> $b } @values;
    is(join('|', @got), join('|', @want), 'integer comparison semantics');
}
done_testing();
