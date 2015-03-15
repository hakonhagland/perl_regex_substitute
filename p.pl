#! /usr/bin/env perl

use feature qw(say);
use strict;
use warnings;

use Carp;
use Data::Dump qw(dd dump);
use Scalar::Util 'reftype';

run_tests();
exit;

sub run_tests {
    # Test cases:
    # Format:
    #   string,       regex,    replacement, expected
    my @test_cases = (
        ['aba',      'a(.*?)a', '$1',      'b'],
        ['yyababaxxa', 'a(.*?)a', '$1',    'yybbxx'],
        ['acccb',    'a(.*?)b', '$1\$',    'ccc$'],
        ['abxybaxy', '(x)(y)',  '${2}3$1', 'aby3xbay3x']
    );

    for (0..$#test_cases) {
        say "Case " . ($_ + 1);
        say "--------";
        my ($str, $regex, $replacement, $expected_result) = @{$test_cases[$_]};
        say "String: '$str'";
        say "Regex: " . dump($regex);
        say "Replacement: '$replacement'";
        say "Expected: '$expected_result'";
        my $result_str = regex_substitute( $str, $regex, $replacement );
        say "Result2: '$result_str'";
        say "Test result: " . (($expected_result eq $result_str) ? "passed" : "failed");
        say "";
    }
}

#
#    $new_string = regex_substitute ( $str, $regex, $replacement, %opt )
#
# DESCRIPTION
#
# This sub routine is based on a stackoverflow.com answer
# by username "Kent Fredric", see http://stackoverflow.com/a/392649/2173773
# and a later code review by user "amon", see:
# http://codereview.stackexchange.com/questions/84081/
#  regex-substitution-using-a-variable-replacement-string-containing-backreferences
#
# This function is intended to be used for the case when you want to do a
#  regex substitution on a string where both the regex and the replacement string
#  is input by the user (and thus not known at
#  compile time) and the replacement string is also allowed to contain backreferences
#  to capture groups in the given regex.
#
#  The straight forward (and careless) application of the 'ee' modifier
#   like  $str =~ /$regex/$replacement/ee;
#
#  should not be used. Since it would allow random code execution
#  (either by accident or by purpose) on the users computer that could
#  have unintended and undesirable consequences.
#
#  This function was written in an attempt to overcome those problems.
#
# INPUT:
# - $str
#   The string to perform the replacements on.
#
# - $regex
#   The regular expression to match. It can contain capture groups.
#   Example:  $regex = qr/a(.*?)a/;
#
# - $replacement
#   The replacement string (must) consists of:
#   1. ordinary literals
#   2. ordinary backreferences
#   3. escaped dollar signs
#   4. escaped backslashes
#
#   A backreference token consists of a dollar sign followed by an
#   integer.  Backreferences can also optionally be surrounded by
#   braces, e.g. "${3}", to avoid ambiguity.
#
#   Example:   $replacement = "a${22}3$1\$\\"
#
#   Here we have:
#    'a'    -> literal
#    '${22} -> backreference to capture group number 22
#    '3'    -> literal
#    '$1'   -> backreference to capture group number 1
#    '\$'   -> escaped dollar
#    '\\'   -> escaped backslash
#
# - %opt
#   A hash of optional arguments:
#    - global  : Boolean, if 1, use global matching and replace. That is,
#                after each replacement, move to the end of that and continue
#                a search for a new match and replace until the end of the
#                string is reached.
#                Default: 1
#                Example: $new_string = regex_substitute (
#                            $str, $regex, $replacement, global => 0 );
#                --> will turn off global match and replace, and only the
#                first match will be replaced.
# ERRORS:
#
# This function croaks on the following exceptions:
#
# - Escape followed by illegal character. A backslash can only be followed by
#   either a backslash or a dollar sign.
# - Escape as the last character of the string.
#   A trailing backslash (that is not preceded by a backslash) is not allowed.
# - A missing right curly brace. For example "${2ab". A starting curly brace
#   after a dollar sign must always be closed by an ending curly brace.
# - A non integer backreference. Backreferences can only be positive integers
# - If there is a backreference out of range. For example, if
#     $replacement = "$3"
#   but there are only two capture groups in $regex.
#
# HISTORY
#
#  version 0.1 - March 2015 : First version.
#
# AUTHOR
#
#  Håkon Hægland  (hakon.hagland@gmail.com)
#
# COPYRIGHT AND LICENSE
#    This code is free software; you may redistribute it and/or
#    modify it under the same terms as Perl itself.
#
sub regex_substitute {
    my ( $str, $regex, $replacement, %opt ) = @_;

    # Do global match and replace by default 
    $opt{global} //= 1;
    
    my $result_str = $str;
    pos( $str ) = 0;
    pos( $result_str ) = 0;
    my $replace_function = _parse_replacement( $replacement );
    while (1) {
        my @captures = $str =~ /\G.*?$regex/s;
        last if @captures == 0; 
        pos($str) = $+[0];
        my $result = $replace_function->(\@captures);
        if ($result_str =~ s/\G.*?\K$regex/$result/s) {
            my $length_of_match = ($+[0] - $-[0]);
            my $offset = length( $result ) - $length_of_match;
            pos( $result_str ) = $+[0] + $offset;
        } else {
            croak "No replacements is unexpected at this point!";
        }
        last unless $opt{global};
    }
    return $result_str;
}

#
#    $replace_func = _parse_replacement ( $replacement )
#
# DESCRIPTION
#
#  Private helper function. Parses a replacement string into tokens
#   and returns a subroutine reference that can be later called with
#   an array reference of capture groups to produce the actual replacement
#   string.
#
# INPUT:
#   - $replacement See the description of $replacement in
#     function "regex_substitute" above.
#  
# RETURN VALUE:
#
#  We return an subroutine reference to a function that can be used to
#   build the substitution.
#
# ERRORS:
#
# See the description of errors in function "regex_substitute" above.
#
sub _parse_replacement {
    my ($replacement) = @_;

    # The @tokens array will contain items from parsing the $replacement
    # string sequentially. The array can contain two types of elements:
    # a) ordinary strings, and b) backreferences.
    # Backreferences are represented as references, in order to be able
    # to separate them from the strings. For example, an item equal to \2
    # is of type reference, and it refers to the number 2 which is the number
    # of the backreference.
    # So, if we encounter a backreference in $replacement, say "${22}",
    # we push it as "\22"..
    # 
    # So, literals are strings, backrefs are refs
    my @tokens;

    # set the initial position to the beginning of the $replacement string
    # This must be done since it is initially "undef"'ed and that cannot be
    # used with the \G regex anchor.
    pos($replacement) = 0;

    # pos is the position before the character to start with
    # so pos = 0, means to start from the beginning
    # if pos == length($replacement), we passed the last character.
    while (pos($replacement) < length($replacement)) {

        # normal literals: These are any character that is not a '\' or a
        # '$'.
        # Note: the 'c' modifier is used, such that pos($replacement) is
        # not reset if the match fails..
        if ($replacement =~ /\G( [^\$\\]+ )/xgc) {
            # if the previous token was literal, concatenate rather than pushing
            # Note: even if it seems like the previous token could not be a literal
            # it could be an escaped literal..
            if (@tokens and not defined reftype $tokens[-1]) {
                $tokens[-1] .= $1;
            }
            else {
                push @tokens, $1;
            }
        }
        # parse escape tokens
        elsif ($replacement =~ /\G [\\]/xgc) {
            
            #handle the only two valid escape sequences: "\" and "$"...
            if ($replacement =~ /\G ([\$\\])/xgc) {
                # if the previous token was literal, concatenate rather than pushing
                if (@tokens and not defined reftype $tokens[-1]) {
                    $tokens[-1] .= $1;
                }
                else {
                    push @tokens, $1;
                }
            }
            elsif ($replacement =~ /\G\z/xgc) {
                croak "Illegal trailing backslash";
            }
            else {
                $replacement =~ /\G (.)/smxgc;
                croak sprintf
                  "Escape can only contain backslash or dollar sign, not U+%4X '%s'",
                  ord $1, $1;
            }
        }
        # handle backrefs tokens:
        elsif ($replacement =~ /\G [\$]/xgc) {
            if ($replacement =~ /\G [{]/xgc) {
                # we slurp all integers after '${':
                if ($replacement =~ /\G( [1-9][0-9]* )/xgc) {
                    my $n = $1;

                    # Note: We subtract 1 from $n, since $0 is not allowed
                    #  and this also allows us to index directly into the
                    #  $captures array (see return value below) later, using
                    #  index = 0, for the first capture group..
                    push @tokens, \($n - 1);
                    if ($replacement =~ /\G [}]/xgc) {
                        # all is OK
                    }
                    else {
                        croak "Expected closing curly brace for \${$n} identifier";
                    }
                }
                else {
                    croak 'Expected ${123} style numeric identifier inside ${...}';
                } 
            }
            #we slurp all integers after the '$' sign:
            elsif ($replacement =~ /\G( [1-9][0-9]* )/xgc) {
                my $n = $1;
                push @tokens, \($n - 1);
            }
            else {
                croak 'Expected $123 or ${123} style number after dollar sign';
            }
        }
        # This should not happen:
        else {
            croak sprintf "Illegal state – expected literal, escape or backref at position %d", pos($replacement);
        }
    }

    # We return an anonymous subroutine
    # This function should be called with an array reference $captures
    # The $captures array should contain all captures from applying the
    #  regex "$regex" to the original string "$str", see the documentation above
    # the "parse_replacement" function for more information on $regex and $str..
    return sub {
        my ($captures) = @_;
        my $buffer = '';

        # Scan the @token array (defined in the parent scope), and
        #  glue together the new string (the return value)from literals
        #  and backrefs (into the capture array).
        # Example: @tokens = ("aaa", \1, "bbb")
        #          $captures = ["ccc"]
        # will produce the string: "aaacccbbb"
        #
        for my $token (@tokens) {
            if (reftype $token) {

                # Note: these indices ($i) are zero-based, i.e. $i == 0
                #  corresponds to capture group number 1. So $i can be
                #  used directly as an index into $captures.
                my $i = $$token; 
                if ($i < @$captures) {
                    $buffer .= $captures->[$i];
                }
                else {
                    croak sprintf 'Unknown backref $%d; there are only %d captures',
                      $$token, 0+@$captures;
                }
            }
            else {
                $buffer .= $token;
            }
        }
        return $buffer;
    };
}

