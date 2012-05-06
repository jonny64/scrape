#!/usr/bin/perl -w
use strict;
use URI;
use Web::Scraper;
use Excel::Template;
use Parallel::Loops;

use Data::Dumper;



# First, create your scraper block
my $countries = scraper {
  process '//*/table[@class="sortable"]//tr', 'countries[]' => scraper {
      my $count = 1;
      process '//tr/td[' . $count++ . ']', 'name' => 'TEXT';
      process '//tr/td[' . $count++ . ']', 'cc' => 'TEXT';
  };
};

my $asns = scraper {
  process '//*/table[@id="asns"]//tr', 'asns[]' => scraper {
      my $count = 1;
      process '//tr/td[' . $count++ . ']', 'asn' => 'TEXT';
      process '//tr/td[' . $count++ . ']', 'company_name' => 'TEXT';
  };
};

my $email = scraper {
  process '//*/div[@id="whois"]//pre', 'text' => 'TEXT';
};


my @report_data;

my $res = _scrape ($countries, "http://bgp.he.net/report/world");
@{$res -> {countries}} = sort {rand () > 0.5? -1 : 1} @{$res -> {countries}};

my $maxProcs = 4;
my $pl = Parallel::Loops -> new ($maxProcs);
$pl -> share (\@report_data);
$pl -> foreach ($res -> {countries}, sub {

	my $country = $_;

	return
		if !$country -> {cc};

	$country -> {name} =~ s/^\s*(.*)\s*$/$1/g;
	$country -> {cc} =~ s/^\s*(\w*)\s*$/$1/g;

	print "processing $country->{cc}...\n";

	my $res = _scrape ($asns, "http://bgp.he.net/country/$country->{cc}"); 
	
	my $maxProcs = 2;
	my $pl = Parallel::Loops -> new ($maxProcs);
	$pl -> share (\@report_data);

	$pl -> foreach ($res -> {asns}, sub {

		my $asn = $_;

		return
			if !$asn -> {asn};

		my $row = {country => $country -> {name}, company_name => $asn -> {company_name}};

		my $res = _scrape ($email, "http://bgp.he.net/$$asn{asn}#_whois");

		if (!$res -> {text} || $res -> {text} !~ m/^e-mail:/) {
			return;
		}

		($row -> {label}) = ($res -> {text} =~ m/^person:\s+(\w+)/m);
		($row -> {email}) = ($res -> {text} =~ m/^e-mail:\s+(\w+)/m);
		($row -> {phone}) = ($res -> {text} =~ m/^phone:\s+(\w+)/m);
		($row -> {first}, $row -> {last}) = split /\s+/, $row -> {label};

		push @report_data, $row;
		print "processing asn $$asn{asn} done. found e-mail\n";
		print Dumper $row;
	});
});

print Dumper \@report_data;

my $template = Excel::Template -> new (filename => 'scrape.xml');
$template -> param (report_data => \@report_data);
$template -> write_file ('scrape.xls');

sub _scrape {

	my ($scraper, $url) = @_;

	sleep 1;
	my $res;
	eval {
		$res = $scraper -> scrape (URI -> new ($url)) 
	};
	warn $@ if $@;

	return $res;
}