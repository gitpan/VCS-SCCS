#!/pro/bin/perl

use strict;
use warnings;

use Data::Dumper;
#use Test::More "no_plan";
use Test::More tests => 71;

BEGIN {
    use_ok ("VCS::SCCS");
    }

like (VCS::SCCS->version (), qr{^\d+\.\d+$},	"Module version");

my $sccs;

my $testfile = "files/s.test.dta";

sub e_is
{
    my ($expr, @args) = @_;
    my $msg = @args ? defined $args[0] ? qq{"$args[0]"} : "undef" : "";
    eval { $sccs = VCS::SCCS->new (@args) };
    is ($sccs, undef, "new->($msg)");
    like ($@, $expr,  ".. fail msg");
    } # e_is

ok (1, "Constructor");
    open my $empty, ">", "s.empty.c";
e_is (qr{needs a valid file name});
e_is (qr{needs a valid file name},	undef);
e_is (qr{needs a valid file name},	"");
e_is (qr{does not exist},		"xxxxx");
e_is (qr{is empty},			"s.empty.c");
    print $empty "Not anymore\n";
    close $empty;
    chmod 0000, "s.empty.c";
e_is (qr{Cannot open},			"s.empty.c");
    unlink "s.empty.c";
e_is (qr{is not a file},		"/dev/null");
e_is (qr{is not a file},		"files");
e_is (qr{start with a checksum},	"Makefile");

ok (1, "Parsing");
ok ($sccs = VCS::SCCS->new ("files/s.test.dta"), "Read and parse large SCCS file");

ok (1, "Metadata");
is ($sccs->file (),		$testfile,	"->file ()");
is ($sccs->checksum (),		52534,		"->checksum ()");
is (scalar $sccs->current (),	70,		"->current () scalar");
is_deeply ([ $sccs->current () ],
	[ 70, "5.39", 5, 39, undef, undef ],	"->current () list");

ok (1, "Deltas");
is ($sccs->version,		"5.39",		"->version ()");
is ($sccs->version (undef),	"5.39",		"->version (undef)");
is ($sccs->version (0),		"5.39",		"->version (0)");
is ($sccs->version (""),	"5.39",		"->version ('')");
is ($sccs->version (53),	"5.22",		"->version (53)");
is ($sccs->version (99),	undef,		"->version (99)");
is ($sccs->version (53, 0),	undef,		"->version (53, 0)");
is ($sccs->revision,		70,		"->revision ()");
is ($sccs->revision (undef),	70,		"->revision (undef)");
is ($sccs->revision (0),	70,		"->revision (0)");
is ($sccs->revision (""),	70,		"->revision ('')");
is ($sccs->revision ("5.38"),	69,		"->revision ('5.38')");
is ($sccs->revision ("9.99"),	undef,		"->revision ('9.99')");
is ($sccs->revision ("5.38",0),	undef,		"->revision ('5.38', 0)");

my $f;
ok ($f = $sccs->flags (),			"->flags ()");
is (ref $f,			"HASH",		".. is hashref");
my %f = %{$f};
ok (exists $f{q},				".. {q} exists");
is ($f{q},			"main_app",	".. {q} has value");
ok (exists $f{v},				".. {v} exists");
is ($f{v},			undef,		".. {v} has no value");

my @users;
ok (@users = $sccs->users (),			"->users ()");
is (scalar @users,		3,		".. has 3 users");
is ($users[0],			"merijn",	".. user 0");
is ($users[1],			"testuser1",	".. user 1");
is ($users[2],			"testuser2",	".. user 2");

is ($sccs->comment (),		"test\n",	"->comment ()");

my $revmap;
ok ($revmap = $sccs->revision_map (),		"->revision_map ()");
is (ref $revmap,		"ARRAY",	".. is arrayref");
is (ref $revmap->[0],		"ARRAY",	".. of arrayrefs");
is ($revmap->[0][0],		1,		".. revision 1");
is ($revmap->[0][1],		"4.1",		".. version  4.1");
is ($revmap->[69][0],		70,		".. revision 70");
is ($revmap->[69][1],		"5.39",		".. version  5.39");

is (length ($sccs->body ()),		261840,	"->body ()      scalar");
is (length ($sccs->body (0)),		261840,	"->body (0)     scalar");
is (length ($sccs->body ("")),		261840,	"->body ('')    scalar");
is (length ($sccs->body (2)),		160788,	"->body (2)     scalar");
is (length ($sccs->body ("4.2")),	160788,	"->body ('4.2') scalar");

my @body;
ok (@body = $sccs->body (),			"->body ()      list");
is ($#body,			6484,		".. 6484 lines");
ok (@body = $sccs->body ("4.2"),		"->body ('4.2') list");
is ($#body,			4237,		".. 4237 lines");
