#!/usr/bin/perl

use lib qw(../../lib);
use strict;
use warnings;
use CGI::Session;
use JSON;
use English;
use Data::Dumper;
use Log::Log4perl qw(:easy);
use MockUI;

#Log::Log4perl->easy_init($DEBUG);
Log::Log4perl->easy_init($ERROR);

use Test::More tests => 6;

package main;

BEGIN {
    use_ok( 'OpenXPKI::Client::UI' );
}

require_ok( 'OpenXPKI::Client::UI' );

my $log = Log::Log4perl->get_logger();

my $session = new CGI::Session(undef, undef, {Directory=>'/tmp'});
my $session_id = $session->id;
ok ($session->id, 'Session id ok');


my $result;
my $client = MockUI->new({
    session => $session,
    logger => $log,
    config => { socket => '/var/openxpki/openxpki.socket' }
});


$result = $client->mock_request({});

is($result->{page}->{label}, 'Please log in');
is($result->{main}->[0]->{action}, 'login!stack');

$result = $client->mock_request({
    'action' => 'login!stack',
    'auth_stack' => "External Dynamic",
});

$result = $client->mock_request({
    'action' => 'login!password',
    'username' => 'raop',
    'password' => 'RA Operator'
});

is($result->{goto}, 'welcome', 'Logged in');