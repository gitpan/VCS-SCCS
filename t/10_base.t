#!/pro/bin/perl

use strict;
use warnings;

use Test::More tests => 13;

BEGIN {
    use_ok ("VCS::SCCS");
    }

like (VCS::SCCS->version (), qr{^\d+\.\d+$},	"Module version");

my $sccs;

my $testfile = "files/s.test.dta";

ok (1, "Parsing");
ok ($sccs = VCS::SCCS->new ("files/s.test.dta"), "Read and parse large SCCS file");

ok (1, "Metadata");
is ($sccs->file (),		$testfile,	"->file ()");
is ($sccs->checksum (),		52534,		"->checksum ()");
is (scalar $sccs->current (),	70,		"->current () 1");

ok (1, "Deltas");
is ($sccs->version,		"5.39",		"->version ()");
is ($sccs->version (53),	"5.22",		"->version (53)");
is ($sccs->revision,		70,		"->revision ()");
is ($sccs->revision ("5.38"),	69,		"->revision ('5.38')");

__END__
print STDERR "Users:    ", $sccs->users,    "\n";
$sccs->body ();
