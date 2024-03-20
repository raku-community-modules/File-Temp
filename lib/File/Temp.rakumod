unit module File::Temp:ver<0.0.11>;

use File::Directory::Tree;

# Characters used to create temporary file/directory names
my @filechars = flat('a'..'z', 'A'..'Z', 0..9, '_');
constant MAX-RETRIES = 10;

my %roster;
my %keptfd;
my Lock $roster-lock;
my Lock $keptfd-lock;
BEGIN { # Because --doc runs END
    $roster-lock = Lock.new;
    $keptfd-lock = Lock.new;
}

my role File::Temp::AutoUnlink {
    submethod DESTROY {
        given self.path {
            if $_.path.IO ~~ :f { # Workaround, should just be $_ ~~ :f
                self.close;
                my $did;
                $roster-lock.protect: {
                    $did = %roster{$_.path}:delete;
                    $_.unlink if $did;
                };
                unless $did {
                    # Something (probably END) already unlinked it
                    # We could have a debug/testing flag do something here.
                }
            }
            # Directories will not get here yet
        }
    }
}

sub make-temp($type, $template, $tempdir, $prefix, $suffix, $unlink) {
    my $count = MAX-RETRIES;
    while $count-- {
        my $tempfile = $template;
        $tempfile ~~ s/ '*' ** 4..* /{ @filechars.roll($/.chars).join }/;
        my $name = $*SPEC.catfile($tempdir,"$prefix$tempfile$suffix");
        next if $name.IO ~~ :e;
        my $fh;
        if $type eq 'file' {
            $fh = try { CATCH { next }; open $name, :rw, :exclusive;  };
            chmod(0o600,$name);
        }
        else {
            try { CATCH { next }; mkdir($name, 0o700) };
        }
        if $unlink {
            $roster-lock.protect: {
                %roster{$name} = $fh;
            };
            $fh &&= $fh does File::Temp::AutoUnlink;
        } elsif ($type eq 'file') {
            $keptfd-lock.protect: {
                %keptfd{$name} = $fh;
            }
        }
        return $type eq 'file' ?? ($name,$fh) !! $name;
    }
    fail "Unable to open temporary $type after {MAX-RETRIES} attempts within \"$tempdir\"";
}

sub tempfile (
    $tmpl? = '*' x 10,          # positional template
    :$tempdir? = $*TMPDIR,      # where to create these temp files
    :$prefix? = '',             # filename prefix
    :$suffix? = '',             # filename suffix
    :$unlink?  = 1,             # remove when program exits?
    :$template = $tmpl          # required named template
) is export {
    make-temp('file', $template, $tempdir, $prefix, $suffix, $unlink)
}

our sub tempdir (
    $tmpl? = '*' x 10,          # positional template
    :$tempdir? = $*TMPDIR,      # where to create tempdir
    :$prefix? = '',             # directory prefix
    :$suffix? = '',             # directory suffix
    :$unlink?  = 1,             # remove when program exits?
    :$template = $tmpl          # required named template
) is export {
    make-temp('dir', $template, $tempdir, $prefix, $suffix, $unlink)
}

END {
    $roster-lock.protect: {
        # Workaround -- directly using %roster.keys not reliable under stress.
        my @rk = %roster.keys;
        for @rk -> $fn {
            if $fn.IO ~~ :f
            {
                %roster{$fn}.close;
                unlink($fn);
            }
            elsif $fn.IO ~~ :d
            {
                rmtree($fn);
            }
        }
        %roster = ();
    }
    $keptfd-lock.protect: {
        my @kk = %keptfd.keys;
        for @kk -> $fn {
            %keptfd{$fn}.close;
        }
        %keptfd = ();
    }
}

=begin pod

=head1 NAME

File::Temp - Create temporary files and directories

=head1 SYNOPSIS

=begin code :lang<raku>

# Generate a temp dir
my $tmpdir = tempdir;

# Generate a temp file in a temp dir
my ($filename, $filehandle) = tempfile;

# Specify a template for the filename
# '*' are replaced with random characters
my ($filename, $filehandle) = tempfile('******');

# Explicitly unlink files at end of program (this is the default)
my ($filename, $filehandle) = tempfile('******', :unlink);

# Specify the directory where the tempfile will be created
my ($filename, $filehandle) = tempfile(:tempdir('/path/to/my/dir'));

# Don't unlink file at end of program
my ($filename, $filehandle) = tempfile(:tempdir('.'), :!unlink);

# Specify a prefix and suffix for the filename
my ($filename, $filehandle) = tempfile(:prefix('foo'), :suffix('.txt'));

=end code

=DESCRIPTION

This module exports two routines:

=item C<tempfile>
Creates a temporary file and returns both a filehandle to that file
opened for writing and the filename of that temporary file.

=item C<tempdir>
Creates a temporary directory and returns the directory name.

=head1 AUTHORS

=item Jonathan Scott Duff
=item Rod Taylor
=item Polgár Márton
=item Tom Browder

=head1 COPYRIGHT AND LICENSE

Copyright 2012 - 2017 Jonathan Scott Duff

Copyright 2018 - 2021 Rod Taylor

Copyright 2022 - 2024 Raku Community

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
