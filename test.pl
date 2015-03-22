#! /usr/bin/env perl

use feature qw(say);
use strict;
use warnings;

use Data::Dump qw(dd dump);
use Test::More;
use String::Regexp::Replace;
use String::Substitution;

# Test cases:
# Format:
#   string,       regex,    replacement, expected
my @test_cases = (
    ['aba',        'a(.*?)a',    '$1',       'b'],
    ['ababab',     'ab',         'x',        'xxx'],
    ['ababab',     '(ab)',       '$1x',      'abxabxabx'],
    ['yyababaxxa', 'a(.*?)a',    '$1',       'yybbxx'],
    ['acccb',      'a(.*?)b',    '$1\$',     'ccc$'],
    ['abxybaxy',   '(x)(y)',     '${2}3$1',  'aby3xbay3x'],
);

plan tests => 2 * scalar(@test_cases);
run_srr_tests(\@test_cases);
run_ss_tests(\@test_cases);
exit;

sub run_ss_tests {
    my ($test_cases) = @_;

    my $passed = 0;
    my $num_tests = @$test_cases + 0;
    for (0..$#$test_cases) {
        my ($str, $regex, $replacement, $expected_result) = @{$test_cases->[$_]};
        my $result_str = String::Substitution::gsub_copy($str, $regex, $replacement);
        is( $expected_result, $result_str, "ss: regular test number " . ($_ + 1));
    }
}

sub run_srr_tests {
    my ($test_cases) = @_;

    my $passed = 0;
    my $num_tests = @$test_cases + 0;
    for (0..$#$test_cases) {
        my ($str, $regex, $replacement, $expected_result) = @{$test_cases->[$_]};
        my $result_str = String::Regexp::Replace::regex_substitute(
            $str, $regex, $replacement
        );
        is( $expected_result, $result_str, "srr: regular test number " . ($_ + 1));
    }
}

