#! /usr/bin/env perl

package String::Regexp::Replace;

use feature qw(say);
use strict;
use warnings;

use Carp;
use Data::Dump qw(dd dump);
use Scalar::Util 'reftype';

# SYNOPSIS
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
#  are input by the user (and thus not known at
#  compile time) and the replacement string is also allowed to contain backreferences
#  to capture groups in the given regex.
#
#  The straight forward (and careless) application of the 'ee' modifier like
#
#     $str =~ /$regex/$replacement/ee;
#
#  should not be used. Since it would allow random code execution
#  (either by accident or by purpose) on the user's computer that could
#  have unintended and undesirable consequences. For example, if the user enters
#
#    $replacement = 'do{ use Env qw(HOME); unlink "$HOME/important.txt" }';
# 
#  the file "important.txt" in the users home directory will be deleted..
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
#   The replacement string (can/must) consists of the following tokens:
#   1. literals,
#   2. backreferences, 
#   3. escaped dollar signs, 
#   4. escaped backslashes.
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
#
#    This code is free software; you may redistribute it and/or
#    modify it under the same terms as Perl itself.
#
sub regex_substitute {
    my ( $str, $regex, $replacement, %opt ) = @_;

    # Do global match-and-replace by default 
    $opt{global} //= 1;
    
    # In order not to mess up the current position when we do global
    #  match-and-replace, we make a copy $result_str of $str here
    #  and do all matching on $str, whereas all replacements is done
    #  on $result_str
    my $result_str = $str;

    #Initialize position to start of string,
    #  so the regex \G assertion will work properly.
    pos( $str ) = 0;
    pos( $result_str ) = 0;
    my $replace_function = _parse_replacement( $replacement );
    while (1) {

        # The 's' modifier is needed to make the dot match newlines
        my @captures = $str =~ /\G.*?$regex/s;
        last if @captures == 0; 

        # Update the starting position for the next search to
        #  the place where the current match ended.
        pos($str) = $+[0];

        # Obtain the replacement string
        my $result = $replace_function->(\@captures);

        # The \K escape is used to keep the stuff to the left of the
        #  $regex match in the replacement when we are using \G as an anchor.
        if ($result_str =~ s/\G.*?\K$regex/$result/s) {

            # Unfortunately @+ and @- refers to the string before
            # we did the substitution. So we need to calculate how
            # much the string expanded or shrunk, to set the correct
            # position for the next search-and-replace.
            my $length_of_match = ($+[0] - $-[0]);
            my $offset = length( $result ) - $length_of_match;
            pos( $result_str ) = $+[0] + $offset;
        } else {
            # Should not happen:
            croak "No replacements is unexpected at this point!";
        }
        last unless $opt{global};
    }
    return $result_str;
}

# SYNOPSIS
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
#   - $replacement
#     See the description of $replacement in
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
    # of a backreference.
    # So, if we encounter a backreference in $replacement, say "${22}",
    # we push it as "\21" (one less than 22: since $0 is not used and it is
    # useful to have the numbers zero-based later also..)
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
    # the "regex_substitute" function for more information on $regex and $str..
    return sub {
        my ($captures) = @_;
        my $buffer = '';

        # Scan the @token array (defined in the parent scope), and
        #  glue together the new string (the return value from this function)
        #  from literals and backrefs (into the capture array).
        # Example: @tokens = ("aaa", \0, "bbb")
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

1;
