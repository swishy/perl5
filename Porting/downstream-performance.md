# Downstream Perl performance branch

This branch tracks Perl development (`blead`) and carries experimental runtime
optimizations. Its initial base is `8ca24e8429`, Perl 5.45.5 development. It is
not an official Perl release. Keep upstream's version number intact; identify
published builds by the downstream Git commit as well as `perl -V`.

## Scope and approach

The aim is faster execution with the same Perl behavior and XS interface.
Keep changes as separate commits so they can be measured, reverted and offered
upstream independently. Retain the unmodified upstream branch as a comparison.
Do not replace the comparison with a differently configured stable Perl build.

The current changes are:

- Numeric key sort: for recognized non-overloaded numeric sorts, extract cached
  IV/UV/NV keys once, stably sort key/pointer pairs and write back SV pointers.
  Preserve generic fallbacks for small lists, references, NaNs and values whose
  warning behavior requires the existing comparator. Mixed integer/float
  comparisons retain upstream's conversion rules, including precision loss.
  Fractional values in integer-sort mode are converted to IV keys even when
  only private integer-cache flags are available; this fixes an edge case
  missed by the earlier 5.44 prototype. Blead's existing reference-counted-stack
  lifetime fix is preserved.
- Large-hash growth experiment: from 4,096 buckets, grow by four where the
  maximum permits it, reducing relink passes at the cost of spare capacity.
  This can increase memory use, and earlier 5.44 measurements showed little
  whole-workload benefit. It is kept separate from numeric sorting for that
  reason. Hash iteration order is unspecified; data, deletion, restricted-hash
  behavior and iterator correctness must still pass their tests.

The earlier 5.44 numeric-sort experiments measured workload-specific gains of
10–27%; those numbers are not blead results. A passing test suite is evidence
for the tested configurations, not a proof covering all Perl behavior.

## Build and use

Use a separate install prefix and rebuild XS modules for that interpreter.
This development branch has no promise of ABI compatibility with stable 5.44.
For a threaded O2 build from this checkout:

```sh
sh Configure -des -Dusedevel -Dusethreads -Doptimize=-O2 \
    -Dprefix="$HOME/.local/perl-performance-blead"
make -j4 test_prep
PERL_SKIP_TTY_TEST=1 TEST_JOBS=4 ./perl t/harness
make install
```

Select the installed interpreter explicitly or put its `bin` directory first
in your application environment's PATH. Keep the system Perl available to the
operating system and its packages. Record the Git revision and complete
`./perl -Ilib -V` output with any distributed build or benchmark.

Velho remains a separate, optional allocator experiment. Build and test Perl
with its normal allocator first. To measure Velho, use a specific tested shared
library through `LD_PRELOAD` for the individual process; do not inject it
system-wide or make Perl core validation depend on it. The allocator source is
maintained in https://github.com/swishy/velho.

## Tests and integration

The upstream `.github/workflows/testsuite.yml` already runs the threaded sanity
build and core tests on forks when Actions is enabled. Enable extended Linux
configurations with the repository Actions variable `CI_FORCE_LINUX=1`, or all
configurations with `DO_EXTENDED_TESTING=1`. Preserve those upstream tests.

New regression files `t/op/sort_numeric_keys.t` and `t/op/hash_growth.t` exercise
sort boundaries, numeric types, stable ties, in-place sorts, and hash growth,
deletions, reinsertion and iteration. Compare stdout and stderr with an
unchanged build for warning/magic edge cases, and run the full harness before
publishing. Include RC-stack/debugging configurations before making compatibility
claims for them. Benchmarks must use the same base commit, compiler, threading
and allocator settings; retain the raw results and account for RSS as well as
time. Compiler changes or allocator changes are separate comparisons.

Keep `origin` pointing to the downstream fork and `upstream` to
https://github.com/Perl/perl5.git. Update from a specific upstream revision and
revalidate after each port. Tag downstream releases with a separate prefix
(such as `performance-...`); preserve upstream's tags. Maintain measured benefits,
known limitations and test evidence here as the patch set evolves.

For any upstream submission, follow [Perl's AI policy](../AI_POLICY.md):
human review and maintenance of code, disclosure of AI assistance, and
human-authored upstream communication and documentation. This downstream guide
is specific to the fork.

## Initial blead measurements (27 October 2026)

Two archive builds from `8ca24e8429`, GCC 13.3.0, threaded O2, normal allocator,
were compared in five rounds with alternating baseline/optimized order and
fixed Perl hash settings. Each reported sample is the median of five sorts of
100,000 elements. This measures sorting only; it does not establish whole-app
speedups, memory savings, or a benefit from the hash-growth experiment.

Median baseline -> optimized times: NV 21.0 -> 16.5 ms; IV 14.5 -> 12.4 ms;
mixed 6.5 -> 6.3 ms; large mixed numbers 6.1 -> 6.3 ms. The first two improved;
the mixed cases were close, including a small regression in the large-number
case. Retain those controls when evaluating future changes.

The benchmark source and all per-round medians are retained below for
reproduction. Run it with each interpreter and its matching `-I.../lib`,
using `PERL_HASH_SEED=42 PERL_PERTURB_KEYS=0` and no allocator preload.

```perl
use strict; use warnings;
use Time::HiRes qw(time);
srand(4242);
sub bench { my ($n,$c,$r)=@_; my @t; for(1..($r//5)){my $t0=time; $c->(); push @t,(time-$t0)*1000;} @t=sort{$a<=>$b}@t; printf "%-20s %7.1f ms\n",$n,$t[int(@t/2)]; }
my @nv  = map { rand() } 1..100_000;
my @iv  = map { int(rand(2_000_001)) - 1_000_000 } 1..100_000;
my @mix = map { $_ % 3 ? $_ + 0.5 : $_ * 1000 } 1..100_000;
my @big = map { $_ % 2 ? 2**62 + $_ : -(2**62) + $_*0.5 } 1..100_000;  # big ints + big fractional
bench("sort NV",   sub { my @x = sort { $a <=> $b } @nv });
bench("sort IV",   sub { my @x = sort { $a <=> $b } @iv });
bench("sort mixed",sub { my @x = sort { $a <=> $b } @mix });
bench("sort bigmix",sub{ my @x = sort { $a <=> $b } @big });
print "done\n";
```

Per-round samples (milliseconds):

```text
sort NV; baseline: 22.5, 21.8, 21.0, 20.5, 20.9; optimized: 17.3, 17.2, 15.8, 16.5, 16.3
sort IV; baseline: 16.0, 14.5, 14.4, 14.3, 14.5; optimized: 14.1, 13.0, 12.4, 12.4, 12.4
sort mixed; baseline: 6.9, 6.5, 6.3, 6.4, 6.9; optimized: 7.4, 6.7, 5.9, 6.3, 5.9
sort bigmix; baseline: 6.8, 6.1, 6.0, 5.9, 6.3; optimized: 6.7, 6.3, 5.9, 6.5, 6.0
```

## Initial validation

The final threaded O2 build passes the complete archive-build core harness:
**2,996 files / 1,435,516 assertions** (213 seconds on the investigation host).
Git-dependent porting checks skip in an archive build; the existing fork CI
runs from a Git checkout. Four focused sort/hash files pass 748 assertions;
the 44 new regression assertions also pass on unchanged blead. The earlier
edge workload's stdout and stderr match baseline byte-for-byte. The first full
attempt encountered sandbox socket restrictions; final validation ran with
socket access. Documentation checks were fixed and included in the clean run.

This is normal-allocator validation. It does not establish results for Velho,
other architectures, long-double/quadmath, or additional debugging/RC-stack
configurations. Builds and detailed logs from this investigation are under
`/tmp/perl-blead-port/`; the clean full-harness output is `full-tests-final.log`.
