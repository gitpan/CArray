use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'CArray',
    'VERSION_FROM' => 'CArray.pm', # finds $VERSION
    'LIBS'	=> [''],   # e.g., '-lm' 
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
    'INC'	=> '',     # e.g., '-I/usr/include/other' 
# POLLUTE is not needed for 5.006

    # additional targets
    'depend' => {
      # update the pod2text readme from the embedded pod
      'pod'  => "\$(DISTVNAME).txt\n",
#      'dist' => "\$(DISTDEFAULT) \$(DISTVNAME).readme\n",
#      '$(DISTVNAME).readme' => "\$(VERSION_FROM)\n" . 
#      	"\tpod2text \$(VERSION_FROM) >\$(DISTVNAME).readme\n",
      # preprocessor only (MSVC => .i file)
      'preonly' => '$(BASEEXT).i' . "\n\t" .
	'$(CC) -P -I$(PERL_INC) $(C_FILES)'."\n",
    }
);
