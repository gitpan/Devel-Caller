package Devel::Caller;
require DynaLoader;
require Exporter;

require 5.005003;

@ISA = qw(Exporter DynaLoader);
@EXPORT_OK = qw( caller_cv called_with );

$VERSION = '0.02';

bootstrap Devel::Caller $VERSION;

1;
__END__

=head1 NAME

Devel::Caller - meatier versions of C<caller>

=head1 SYNOPSIS

 use Devel::Caller qw(caller_cv);
 $foo = sub { print "huzzah\n" if $foo == caller_cv(0) };
 $foo->();  # prints huzzah

 use Devel::Caller qw(called_with);
 my @foo;
 sub foo { print "huzzah" if \@foo == (called_with 0)[0] }
 foo(@foo); # should print huzzah


=head1 DESCRIPTION

=over

=item caller_cv($level)

C<caller_cv> gives you the coderef of the subroutine being invoked at
the call frame indicated by the value of $level

=item called_with($level, $names)

C<called_with> returns a list of references to the original arguments
to the subroutine at $level.  if $names is true, the names of the
variables will be returned instead

constants are returned as C<undef> in both cases

=head1 BUGS

All of these routines are susceptible to the same limitations as
C<caller> as described in L<perlfunc/caller>

The deparsing of the optree perfomed by called_with is fairly simple-minded
and so a bit flaky.  It's know to currently chokes structures such as this:

   foo( [ 'constant' ] );

Also, on perl 5.005_03

   use vars qw/@bar/;
   foo( @bar = qw( some value ) );

is broken as it generates real split ops rather than optimising it
into a constant assignment at compile time as in newer perls.

=head1 SEE ALSO

L<perlfunc/caller>, L<PadWalker>, L<Devel::Peek>

=head1 AUTHOR

Richard Clamp E<lt>richardc@unixbeard.netE<gt> with close reference to
PadWalker by Robin Houston

=head1 COPYRIGHT

Copyright (c) 2002, Richard Clamp. All Rights Reserved.  This module
is free software. It may be used, redistributed and/or modified under
the same terms as Perl itself.

=cut
