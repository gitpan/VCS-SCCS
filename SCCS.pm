#!/pro/bin/perl

# Copyright (c) 2007-2007 H.Merijn Brand.  All rights reserved.

package VCS::SCCS;

use strict;
use warnings;

use POSIX  qw(mktime);
use Carp;

use vars qw( $VERSION );
$VERSION = "0.06";

### ###########################################################################

# We can safely use \d instead of [0-9] for this ancient format

sub new
{
    my $proto = shift;
    my $class = ref ($proto) || $proto	or return;

    # We can safely rule out "0" as a valid filename, ans 99.9999% of
    # SCCS source files start with s.
    my $fn = shift		or croak ("SCCS needs a valid file name");
    -e $fn			or croak ("$fn does not exist");
    -f $fn			or croak ("$fn is not a file");
    -s $fn			or croak ("$fn is empty");

    open my $fh, "<", $fn	or croak ("Cannot open '$fn': $!");

    # Checksum
    # ^Ah checksum
    <$fh> =~ m/^\cAh(\d+)$/	or croak ("SCCS file $fn is supposed to start with a checksum");

    my %sccs = (
	file		=> $fn,

	checksum	=> $1,
	delta		=> {},
	users		=> [],
	flags		=> {},
	comment		=> "",
	body		=> undef,

	current		=> undef,
	vsn		=> {},	# version to revision map
	);

    # Delta's At least one! ^A[ixg] ignored
    # ^As inserted/deleted/unchanged
    # ^Ad D version date time user v_new v_old
    # ^Am MR
    # ^Ac comment
    # ^Ae
    $_ = <$fh>;
    while (m{^\cAs (\d+)/(\d+)/(\d+)$}) {

	my @delta;

	my ($l_ins, $l_del, $l_unc) = map { $_ + 0 } $1, $2, $3;

	{   local $/ = "\cAe\n";
	    @delta = split m/\n/, scalar <$fh>;
	    }

	my ($type, $vsn, $v_r, $v_l, $v_b, $v_s, $y, $m, $d, $H, $M, $S, $user, $cur, $prv) =
	    (shift (@delta) =~ m{
		\cAd				# Delta
		\s+ ([DR])			# Type	Delta/Remove?
		\s+ ((\d+)\.(\d+)
		     (?:\.(\d+)(?:\.(\d+))?)?)	# Vsn	%R%.%L%[.%B%[.%S%]]
		\s+ (\d\d)/(\d\d)/(\d\d)	# Date	%E%
		\s+ (\d\d):(\d\d):(\d\d)	# Time	%U%
		\s+ (\S+)			# User
		\s+ (\d+)			# current rev
		\s+ (\d+)			# new     rev
		\s*$
		}x);
	$y += $y < 70 ? 2000 : 1900; # SCCS is not Y2k safe!

	# We do not have "R" entries
	$type eq "R" and warn ("Delta type R has never been tested!");

	my @mr   = grep { s/^\cAm\s*// } @delta; # MR number(s)
	my @cmnt = grep { s/^\cAc\s*// } @delta; # Comment

	$sccs{current} ||= [ $cur, $vsn, $v_r, $v_l, $v_b, $v_s ];
	$sccs{delta}{$cur} = {
	    lines_ins	=> $l_ins,
	    lines_del	=> $l_del,
	    lines_unc	=> $l_unc,

	    type	=> $type,

	    version	=> $vsn,
	    v_r		=> $v_r,
	    v_l		=> $v_l,
	    v_b		=> $v_b,
	    v_s		=> $v_s,

	    date	=> ($y * 100 + $m) * 100 + $d,
	    time	=> ($H * 100 + $M) * 100 + $S,
	    stamp	=> mktime ($S, $M, $H, $d, $m - 1, $y - 1900, -1, -1, -1),

	    comitter	=> $user,

	    mr		=> join (", ", @mr),
	    comment	=> join ("\n", @cmnt),

	    prev	=> $prv,
	    };
	$sccs{vsn}{$vsn} = $cur;
	$_ = <$fh>;
	}

    # Users
    # ^Au
    # user1
    # user2
    # ...
    # ^AU
    if (m{^\cAu}) {
	{   local $/ = "\cAU\n";
	   $sccs{users} = [ (<$fh> =~ m{^([A-Za-z].*)$}gm) ];
	   }
	$_ = <$fh>;
	}

    # Flags
    # ^Af q Project name
    # ^Af v ...
    while (m/^\cAf \s+ (\S) \s* (.+)?$/x) {
	$sccs{flags}{$1} = $2;
	$_ = <$fh>;
	}

    # Comment
    # ^At comment
    while (s/^\cA[tT]\s*//) {
	m/\S/ and $sccs{comment} .= $_;
	$_ = <$fh>;
	}

    # Body
    local $/ = undef;
    $sccs{body} = [ split "\n", $_ . <$fh> ];
    close $fh;

    return bless \%sccs, $class;
    } # new

sub file
{
    my $self = shift;
    return $self->{file};
    } # file

sub checksum
{
    my $self = shift;
    return $self->{checksum};
    } # checksum

sub users
{
    my $self = shift;
    return @{$self->{users}};
    } # users

sub flags
{
    my $self = shift;
    return { %{$self->{flags}} };
    } # flags

sub comment
{
    my $self = shift;
    return $self->{comment};
    } # comment

sub current
{
    my $self = shift;
    $self->{current} or return undef;
    wantarray ? @{$self->{current}} : $self->{current}[0];
    } # current

sub delta
{
    my $self = shift;
    } # delta

sub version
{
    my $self = shift;
    unless ($self && ref $self) {
	return $VERSION;
	}

    $self->{current} or return undef;

    # $self->version () returns most recent version
    my @args = @_       or return $self->{current}[1];
    my $rev  = $args[0] or return $self->{current}[1];

    # $self->revision (12) returns version for that revision
    @args == 1 && exists $self->{delta}{$rev} and
	return $self->{delta}{$rev}{version};

    return undef;
    } # version

sub revision
{
    my $self = shift;

    $self->{current} or return undef;

    # $self->revision () returns most recent revision
    my @args = @_       or return $self->{current}[0];
    my $vsn  = $args[0] or return $self->{current}[0];

    # $self->revision (12) returns version for that revision
    @args == 1 && exists $self->{vsn}{$vsn} and
	return $self->{vsn}{$vsn};

    return undef;
    } # revision

sub revision_map
{
    my $self = shift;

    $self->{current} or return undef;

    return [ map { [ $_ => $self->{delta}{$_}{version} ] }
	sort { $a <=> $b }
	    keys %{$self->{delta}} ];
    } # revision

sub translate_keywords
{
    # '%W%[ \t]*%G%'	=>			"$""Id""$"),
    # '%W%[ \t]*%E%'	=>			"$""Id""$"),
    # '%W%'	=>				"$""Id""$"),
    # '%Z%%M%[ \t]*%I%[ \t]*%G%'	=>	"$""SunId""$"),
    # '%Z%%M%[ \t]*%I%[ \t]*%E%'	=>	"$""SunId""$"),
    # '%M%[ \t]*%I%[ \t]*%G%'	=>		"$""Id""$"),
    # '%M%[ \t]*%I%[ \t]*%E%'	=>		"$""Id""$"),
    # '%M%'	=>				"$""RCSfile""$"),
    # '%I%'	=>				"$""Revision""$"),
    # '%G%'	=>				"$""Date""$"),
    # '%E%'	=>				"$""Date""$"),
    # '%U%'	=>				""),
    } # translate_keywords

sub body
{
    my $self = shift;

    $self->{body} && $self->{current} or return undef;
    my $r = shift || $self->{current}[0];

    exists $self->{vsn}{$r} and $r = $self->{vsn}{$r};

    my @lvl = ([ 1, "I", 0 ]);
    my @body;

#   my $v = sub {
#	join " ", map { sprintf "%s:%02d", $_->[1], $_->[2] } @lvl[1..$#lvl];
#	}; # v

    my $w = 1;
    for (@{$self->{body}}) {
	if (m/^\cAE\s+(\d+)$/) {
	    my $e = $1;
#	    print STDERR $v->(), " END $e (@{$lvl[-1]})\n";
	    # SCCS has a seriously ill design so that chunks can overlap
	    # Below example is from actual code
	    # D 9
	    # E 9
	    # I 9
	    #  D 10
	    #  E 10
	    #  I 10
	    #   D 53
	    #   E 53
	    #   I 53
	    #   E 53
	    #   I 23
	    #    D 31
	    #    E 31
	    #    I 31
	    #     D 45
	    #     E 45
	    #     I 45
	    #     E 45
	    #     D 53 ---+
	    #    E 31     |
	    #   E 23      |
	    #  E 10       |
	    # E 9         |
	    # D 7         |
	    # E 7         |
	    # I 7         |
	    #     E 53 <--+
	    #  I 53
	    #  E 53
	    #  D 53
	    #  E 53
	    #  I 53
	    #  E 53
	    # E 7
	    foreach my $x (reverse 0 .. $#lvl) {
		$lvl[$x][2] == $e or next;
		splice @lvl, $x, 1;
		last;
		}
	    $w = (grep { $_->[0] == 0 } @lvl) ? 0 : 1;
	    next;
	    }
	if (m/^\cAI\s+(\d+)$/) {
	    push @lvl, [ $r >= $1 ? 1 : 0, "I", $1 ];
	    $w = (grep { $_->[0] == 0 } @lvl) ? 0 : 1;
	    next;
	    }
	if (m/^\cAD\s+(\d+)$/) {
	    push @lvl, [ $r >= $1 ? 0 : 1, "D", $1 ];
	    $w = (grep { $_->[0] == 0 } @lvl) ? 0 : 1;
	    next;
	    }
	if (m/^\cA(.*)/) {
	    warn "Unsupported SCCS control: ^A$1, line skipped";
	    next;
	    }
	$w and push @body, $_;
#	printf STDERR "%2d.%04d/%s: %-29.29s |%s\n", $r, scalar @body, $w, $v->(), $_;
	}
    return wantarray ? @body : join "\n", @body, "";
    } # body

1;

__END__

=head1 NAME

VCS::SCCS - OO Interface to SCCS files

=head1 SYNOPSIS

 use VCS::SCCS;

 my $sccs = VCS::SCCS->new ("SCCS/s.file.pl");   # Read and parse

 # Meta info
 my $fn = $sccs->file ();            # s.file.pl
 my $cs = $sccs->checksum ();        # 52534
 my @us = $sccs->users ();           # qw( merijn user )
 my $fl = $sccs->flags ();           # { q => "Test applic", v => undef }
 my $cm = $sccs->comment ();         # ""
 my $cr = $sccs->current ();         # 70
 my @cr = $sccs->current ();         # ( 70, "5.39", 5, 39 )

 # Delta related
 my $xx = $sccs->delta (...);   -- NYI --
 my $vs = $sccs->version ();         # "5.39"
 my $vs = $sccs->version (69);       # "5.38"
 my $rv = $sccs->revision ();        # 70
 my $rv = $sccs->revision ("5.37");  # 68
 my $rm = $sccs->revision_map ();    # [ [ 1, "4.1" ], ... [ 70, "5.39" ]]

 # Content related
 my $body_70 = $sccs->body ();       # file.pl @70 incl NL's
 my @body_70 = $sccs->body ();       # file.pl @70 list of chomped lines
 my @body_69 = $sccs->body (69);     # same for file.pl @96
 my @body_69 = $sccs->body ("5.38"); # same
 -- NYI --
 my $diff = $sccs->diff (67);        # unified diff between rev 67 and 70
 my $diff = $sccs->diff (63, "5.37");# unified diff between rev 63 and 68

=head1 DESCRIPTION

SCCS was the dominant version control system until the release of the
Revision Control System. Today, SCCS is generally considered obsolete.
However, its file format is still used internally by a few other revision
control programs, including BitKeeper and TeamWare. Sablime[1] also allows
the use of SCCS files. The SCCS file format uses a storage technique called
interleaved deltas (or the weave). This storage technique is now considered
by many revision control system developers as key to some advanced merging
techniques, such as the "Precise Codeville" ("pcdv") merge.

This interface aims at the possibility to read those files, without the
need of the sccs utility set, and open up to the possibility of scripts
that use it to convert to more modern VCSs like git, Mercurial, CVS, or
subversion.

=head1 FUNCTIONS

=head2 Meta function

=over 4

=item new (<file>)

The constructor only accepts a single argument: the SCCS file. this will
typically be something like C<SCCS/s.file.c>.

If anything in that file makes C<new ()> believe that it is not a SCCS
file, it will return undef. In this stage, there is no way yet to tell
why C<new ()> failed.

=item file

Returns the name of the parsed file. Useful if you have more than a
single $sccs object.

=item checksum

Returns the checksum that was stored in the file. This module does not
check if it is valid, nor does it have functionality to calculate a new
checksum.

=item users

Returns the list of users that was recorded in this file as authorized
to make deltas/changes.

=item flags

Returns a hash of the flags set for this file (if set at all). VCS::SCCS
does not do anything with these flags. They are here for the end-user only.

Note that not all flags are supported by all versions of C<admin>, like
C<x> is supported on HP-UX, but not in CSSC.

=over 4

=item t <type of program>

File has a user defined value for the %Y% keyword.

=item v [<program name>]

File was flagged to prompt for MR (using <program name> for validation).

=item i <keyword string>

File was flagged to require id keywords.

=item b

File was allowed to pass -b to get to create branch deltas.

=item m <module name>

File has a user defined value for the %M% keyword.

=item f <floor>

File was given a floor: the lowest release, a number from 1 to 9998, which
may be get for editing.

=item c <ceiling>

File was given a ceiling: a number less than or equal to 9999, which can
be retrieved by a get command.

=item d <default sid>

File was given a default delta number SID.

=item n

File created null deltas for skipped major versions.

=item j

File was flagged to allow concurrent edits on the same SID.

=item l <lock releases>

File was given a list of releases to which deltas can no longer be made.

=item q <user defined text>

File has a user defined value for the %Q% keyword.

=item x

File was flagged to set execution bit on get.

=item z <reserved for use in interfaces>

File was flagged to set execution bit on get.

=back

=item comment

The comment that was added when the file was created.

=item current

In scalar context returns the current revision number. That is the
number of the file that would be restored by get with no arguments.

In list context, it returns the current revision, version and parts
of the version, something like C<(70, "5.39", 5, 39, undef, undef)>.
The last 4 numbers are the equivalent of the keywords %R%, %L%, %B%,
and %S% for that release.

=back

=head2 Delta functions

=over 4

=item delta

NYI

=item version
=item version (<revision>)

If called without argument, it returns the last version, just as
the second return value of C<current ()> in list context.

If called with a revision argument, it returns you the version that
matches that revision. It returns undef if no matching version is
found.

=item revision
=item revision (<version>)

If called without argument, it returns the last revision, just as
C<current ()> returns in scalar context.

If called with a version argument, it returns you the revision that
matches that version. It returns undef if no matching revision is
found.

=item revision_map

Returns an anonymous list of C<revision> - C<version> pairs (in
anonymous lists).

=back

=head2 Content function

=over 4

=item body
=item body (<revision>)
=item body (<version>)

In scalar context returns the full body for the given revision.
If no revision is passed, the current (most recent) revision is
used. If a version is passed, the matching revision will be used.
If the is no matching version or revision, C<body ()> returns
C<undef>.

In list context, C<body ()> returns the list of chomped lines for
the given revision.

=item diff

NYI

=item translate_keywords

NYI

plan is to accept either a single string, like "CVS", or "RCS" and
translate the SCCS keywords to the corresponding CVS or RCS keywords
(if possible), or to accept a hash that defines a translation table
and have VCS::SCCS fill in the missing entries with defaults.

=back

=head1 SPECIFICATION

SCCS file format is reasonable well documented. I have included a
manual page for sccsfile for HP-UX in doc/

=head1 EXAMPLES

See the files in examples/ for my attempts to start convertors to
other VCSs

=head1 LIMITATIONS

As this module is created as a base for conversion to more useful
and robust VCSs, it is a read-only interface to the SCCS files.

=head1 BUGS

Tested on our own repositories with perl-5.8.x-dor and perl-5.10.0. 

=head1 TODO

* improve documentation
* implement delta () and diff ()
* more tests
* sccs2rcs
* sccs2cvs
* sccs2git
* sccs2hg
* sccs2svn
* errors and warnings
* provide hooks to VCS::

=head1 DIAGNOSTICS

First errors, than diagnostics ...

=head1 SEE ALSO

SCCS - http://en.wikipedia.org/wiki/Source_Code_Control_System

CSSC - https://sourceforge.net/projects/cssc
A GNU project that aims to be a drop-in replacement for SCCS. It is
written in c++ and therefor disqualifies to be used at any older OS
that does support SCCS but has no C++ compiler. And even if you have
one, there is a good chance it won't build or does not bass the basic
tests. I didn't get it to work.

VCS - http://search.cpan.org/dist/VCS

=head1 AUTHOR

H.Merijn Brand <h.m.brand@xs4all.nl>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007-2007 H.Merijn Brand

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
