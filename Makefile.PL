use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $module = 'Caller.pm';
WriteMakefile(
              'NAME'      => 'Devel::Caller',
              'VERSION_FROM' => $module, # finds $VERSION
              'LIBS'      => [''],   # e.g., '-lm'
              'PREREQ_PM' => { 'Test::More'=> 0 },
              'DEFINE'    => '',     # e.g., '-DHAVE_SOMETHING'
              'INC'       => '',     # e.g., '-I/usr/include/other'
             );


sub MY::postamble {
    return <<EOF
README: $module
\tpod2text $module > README
EOF
}
