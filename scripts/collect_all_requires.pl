#! /usr/bin/perl

use File::Find;

# get_provides_requires($specfile, *requires)
sub get_requires {
    my $name;
    my $line;
    my $specfile = shift @_;
    local (*requires) = @_;
    my @files = ();
    my @subpackages = ();
    my @array;
    my $file, $subpackage;
    my $a;

    open FILE, "<$specfile";
    while (<FILE>) {

	if (/^Name:\s+(.*)/) {
	    $name=$1;
	} elsif (/^BuildRequires:\s+(.*)/) {
#/\s+|=|%\{.*\}/
	    $line = $1;
	    $line =~ s/\s*([<>=]+)\s+/$1/g;
	    @array = split /\s+|%\{.*\}/, $line;
	    foreach $a (@array) {
		$a =~ s/([<>=]+)/ $1 /g;
		push @requires, "$a\n";
	    }
	} elsif (/^%package\s+(.*)/) {
	    @array = split /\s+|\-\w\s+/, $1;
	    push @subpackages, @array;
	} elsif ( /^%files\s+-n\s+(.*)/ ) {
	    @array = split /\s+|\-\w\s+/, $1;
	    push @files, @array;
	} 
    }
    close FILE;

    return $name;
}

sub found {
    if ($File::Find::name ne ".") { $File::Find::prune = 1 ; }
    if (/.*\.spec/) {
	push @filelist, ($File::Find::name);
    }
}

$specfile=$ARGV[0];

if (!$specfile) {
    find (\&found, './');
    @filelist || die "no specfile found";
    ($#filelist == 0) 
	|| die "more than one specfile found; specify specfile from: @filelist";
    $specfile=$filelist[0];
}

$specfile="./$specfile" unless $specfile =~ /^\/.*/;
-e "$specfile" || die "File $specfile not found";

$name = "";
@requires = ();

$name = get_requires ($specfile, *requires);
foreach $a (@requires) {
    print "$a";
}
#print "\n";
#print "@requires\n";
