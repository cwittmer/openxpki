# OpenXPKI::Server::Workflow::Condition::InitialEnrollmentOrRenewal.pm
# Written by Alexander Klink for the OpenXPKI project 2006
# Copyright (c) 2006 by The OpenXPKI Project
# $Revision$
package OpenXPKI::Server::Workflow::Condition::InitialEnrollmentOrRenewal;

use strict;
use warnings;
use base qw( Workflow::Condition );
use Workflow::Exception qw( condition_error configuration_error );
use OpenXPKI::Server::Context qw( CTX );
use OpenXPKI::Debug 'OpenXPKI::Server::API::Workflow::Condition::InitialEnrollmentOrRenewal';
use OpenXPKI::DN;
use English;

use DateTime;

use Data::Dumper;

__PACKAGE__->mk_accessors( 'RDN_filter' );

sub _init
{
    my ( $self, $params ) = @_;
    if (exists $params->{RDN_filter}) {
        $self->RDN_filter($params->{RDN_filter});
    }
}

sub evaluate {
    ##! 16: 'start'
    my ( $self, $workflow ) = @_;

    my $context   = $workflow->context();
    ##! 64: 'context: ' . Dumper($context)
    my $pki_realm = CTX('session')->get_pki_realm(); 

    my $subject = $context->param('csr_subject');
    ##! 16: 'subject: ' . $subject
    my $dn = OpenXPKI::DN->new($subject);

    my @rdns = $dn->get_rdns();
    my @filtered_rdns;
    if (defined $self->RDN_filter()) { # we have to filter the rdns
        my @filters = split(/,/, $self->RDN_filter());
        foreach my $filter (@filters) {
            ##! 128: 'filter: ' . $filter
            push @filtered_rdns, (grep /^$filter=/, @rdns);
        }
    }
    my $dynamic_subject;
    ##! 128: '@filtered_rdns: ' . Dumper \@filtered_rdns
    if (scalar @filtered_rdns > 0) { # we have filtered RDNs, match them all
        my @dynamic;
        foreach my $filtered_rdn (@filtered_rdns) {
            push @dynamic, "%$filtered_rdn%";
        }
        $dynamic_subject = \@dynamic;
    }
    else { # match the complete subject
        $dynamic_subject = $subject;
    }
    my $dbi = CTX('dbi_backend');

    my $now = DateTime->now()->epoch();

    # look up valid certificates matching the subject
    my $certs = $dbi->select(
        TABLE   => 'CERTIFICATE',
        COLUMNS => [
            'NOTBEFORE',
            'NOTAFTER',
            'IDENTIFIER',
        ],
        DYNAMIC => {
            'SUBJECT'   => $dynamic_subject, # this is either scalar or arrayref!
            'STATUS'    => 'ISSUED',
            'PKI_REALM' => $pki_realm,
        },
        REVERSE => 1,
        VALID_AT => time,
    );

    ##! 128: 'certs: ' . Dumper $certs

    if (defined $certs && scalar @{$certs} > 0) {
            # this is a renewal, save number of matching certificates
            # and identifier and notafter date of first one in context
            # for later use.
            # the "first" one is the one with the latest notbefore
            # date, so we assume it has the most recent information
            # and can thus be used as a "blueprint" for the new
            # certificate
            $context->param(
                'current_valid_certificates' => scalar @{$certs}
            );
            $context->param(
                'current_identifier' => $certs->[0]->{IDENTIFIER},
            );
            $context->param(
                'current_notafter' => $certs->[0]->{NOTAFTER},
            );
            condition_error('I18N_OPENXPKI_SERVER_WORKFLOW_CONDITION_INITIALENROLLMENTORRENEWAL_NO_INITIAL_ENROLLMENT_VALID_CERTIFICATE_PRESENT');
    }
    ##! 16: 'end'
    return 1;
}

1;

__END__

=head1 NAME

OpenXPKI::Server::Workflow::Condition::InitialEnrollmentOrRenewal

=head1 SYNOPSIS

<action name="do_something">
  <condition name="is_initial_enrollment"
             class="OpenXPKI::Server::Workflow::Condition::InitialEnrollmentOrRenewal">
  </condition>
</action>

=head1 DESCRIPTION

The condition checks if a SCEP request is an initial enrollment request
or a renewal. The condition has a configuration parameter "RDNmatch",
which allows one to specify which parts of the subject DN have to
match.
If it is undefined, the whole subject DN is taken as a search criteria.
It returns true if no valid certificate with the requested DN is found
in the certificate database and throws a condition_error if at least one
is found. 
In this case, it also saves the number of certificates in the context
parameter 'current_valid_certificates' and the identifier of the one 
with the longest notafter date in the context parameter
'current_identifier'.
The corresponding notafter date is saved in the 'current_notafter'
context field to be checked later.