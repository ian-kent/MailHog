package MailHog::Server::SMTP::RFC3461;

=head NAME

MailHog::Server::SMTP::RFC3461 - Delivery status notification extension

=head2 DESCRIPTION

RFC3461 implements the DSN extension in SMTP.



=head2 CONFIGURATION

=cut

use Modern::Perl;
use Moose;

#------------------------------------------------------------------------------

sub register {
	my ($self, $smtp) = @_;

	# Register this RFC
    if(!$smtp->has_rfc('RFC5321')) {
        die "MailHog::Server::SMTP::RFC3461 requires RFC5321";
    }
    $smtp->register_rfc('RFC3461', $self);

	# Add a list of commands to EHLO output
    $smtp->register_helo(sub {
        my ($session) = @_;
        return "DSN";
    });

    # Replace RFC5321's MAIL command
    $smtp->register_command('MAIL', sub {
        my ($session, $data) = @_;
        $self->mail($session, $data);
    });

    # Replace RFC5321's RCPT command
    $smtp->register_command('RCPT', sub {
        my ($session, $data) = @_;
        $self->rcpt($session, $data);
    });
}

#------------------------------------------------------------------------------

sub mail {
    my ($self, $session, $data) = @_;

    $session->log("Using MAIL from RFC3461 (DSN)");

    if(my ($ret) = $data =~ /RET=(FULL|HDRS)/i) {
        # Strip off RET parameter
        $data =~ s/\s*RET=(?:FULL|HDRS)//i;

        $session->log("Using RET from RFC3461 (DSN), RET = $ret");

        $session->stash('mail_params')->{RET} = $ret;
    }

    if(my ($envid) = $data =~ /ENVID=(<[^>]*>)/i) {
        # Strip off ENVID parameter
        $data =~ s/\s*ENVID=<[^>]*>//i;

        $session->log("Using ENVID from RFC3461 (DSN), ENVID = $envid");

        $session->stash('mail_params')->{ENVID} = $envid;
    }

    if(my $rfc = $session->smtp->has_rfc('RFC1870')) {
        return $rfc->mail($session, $data);
    }
    return $session->smtp->has_rfc('RFC5321')->mail($session, $data);
}

#------------------------------------------------------------------------------

sub rcpt {
    my ($self, $session, $data) = @_;

    $session->log("Using RCPT from RFC3461 (DSN)");

    if(my ($notify) = $data =~ /NOTIFY=((?:(?:\w+),?)+)/i) {
        # Strip off NOTIFY parameter
        $data =~ s/\s*NOTIFY=(?:(?:\w+),?)+//i;

        $session->log("Using NOTIFY from RFC3461 (DSN), notify: $notify");

        # TODO validate notify
        # can be NEVER | DELAY,SUCCESS,FAILURE
        $session->stash('rcpt_params')->{NOTIFY} = $notify;
    }

    if(my ($orcpt) = $data =~ /ORCPT=((?:[\w\d]+);(?:[^\s\r\n]*))/i) {
        # Strip off ORCPT parameter
        $data =~ s/\s*ORCPT=((?:[\w\d]+);(?:[^\s\r\n]*))//i;

        $session->log("Using ORCPT from RFC3461 (DSN), orcpt: $orcpt");

        $session->stash('rcpt_params')->{ORCPT} = $orcpt;
    }

    if(my $rfc = $session->smtp->has_rfc('RFC1870')) {
        return $rfc->rcpt($session, $data);
    }
    return $session->smtp->has_rfc('RFC5321')->rcpt($session, $data);
}

#------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;