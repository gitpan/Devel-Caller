package Devel::Caller;
require DynaLoader;
require Exporter;

use PadWalker ();

require 5.005003;

@ISA = qw(Exporter DynaLoader);
@EXPORT_OK = qw( caller_cv caller_args caller_vars called_with called_as_method );

$VERSION = '0.11';

bootstrap Devel::Caller $VERSION;

sub caller_args {
    my $level = shift;
    package DB;
    () = caller( $level + 1 );
    return @DB::args
}

*caller_vars = called_with;
sub called_with {
    my $level = shift;
    my $names = shift || 0;

    my $cx = PadWalker::_upcontext($level + 1);
    return unless $cx;

    my $cv = caller_cv($level + 2);
    _called_with($cx, $cv, $names);
}

sub caller_cv {
    my $level = shift;
    my $cx = PadWalker::_upcontext($level + 1);
    return unless $cx;
    return _context_cv($cx);
}


sub called_as_method {
    my $level = shift || 0;
    my $cx = PadWalker::_upcontext($level + 1);
    return unless $cx;
    _called_as_method($cx);
}

1;
__END__

=head1 NAME

Devel::Caller - meatier versions of C<caller>

=head1 SYNOPSIS

 use Devel::Caller qw(caller_cv);
 $foo = sub { print "huzzah\n" if $foo == caller_cv(0) };
 $foo->();  # prints huzzah

 use Devel::Caller qw(called_with);
 sub foo { print called_with(0,1); }
 foo( my @foo ); # should print '@foo'

=head1 DESCRIPTION

=over

=item caller_cv($level)

C<caller_cv> gives you the coderef of the subroutine being invoked at
the call frame indicated by the value of $level

=item caller_args($level)

Returns the arguments passed into the caller at level $level

=item caller_vars( $level, $names )
=item called_with($level, $names)

C<called_with> returns a list of references to the original arguments
to the subroutine at $level.  if $names is true, the names of the
variables will be returned instead

constants are returned as C<undef> in both cases

=item called_as_method($level)

C<called_as_method> returns true if the subroutine at $level was
called as a method.

=head1 BUGS


All of these routines are susceptible to the same limitations as
C<caller> as described in L<perlfunc/caller>

The deparsing of the optree perfomed by called_with is fairly simple-minded
and so a bit flaky.

=over

=item

The code is currently inaccurate in this case:

 print foo( $bar ), baz( $quux );

When returning answers about the invocation of baz it will mistakenly
return the answers for the invocation of foo so you'll see '$bar'
where you expected '$quux'.

A workaround is to rewrite the code like so:

 print foo( $bar );
 print bar( $baz );

A more correct fix is left as a TODO item.

=item

Under perl 5.005_03

 use vars qw/@bar/;
 foo( @bar = qw( some value ) );

will not deparse correctly as it generates real split ops rather than
optimising it into a constant assignment at compile time as in later
releases of perl.

=item

On perl 5.8.x compiled with ithreads it's not currently supported to
retrieve package variables from the past.  Instead the empty string is
returned for the name, and undef is returned when the value is
requested.

Though crappy, this is an improvement on causing your application to
segfault.

=back


=head1 SEE ALSO

L<perlfunc/caller>, L<PadWalker>, L<Devel::Peek>

=head1 AUTHOR

Richard Clamp <richardc@unixbeard.net> with close reference to
PadWalker by Robin Houston

=head1 COPYRIGHT

Copyright (c) 2002, 2003, 2006 Richard Clamp. All Rights Reserved.
This module is free software. It may be used, redistributed and/or
modified under the same terms as Perl itself.

=cut
