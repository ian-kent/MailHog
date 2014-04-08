package MailHog::Server::SMTP::RFC1870;

=head NAME

MailHog::Server::SMTP::RFC1870 - SIZE extension

=head2 DESCRIPTION

RFC1870 implements the SIZE extension in SMTP.

It advertises the maximum message size in the EHLO response, and enforces
the maximum message size on the DATA command. It also provides an up-front
test on the RCPT command to reject messages which would take the user over-limit.

=head2 CONFIGURATION

The maximum message size is set in
    $config->{maximum_size}
and applies even if this RFC is disabled.

The broadcast option is set in 
    $config->{extensions}->{size}->{broadcast}
and determines whether the SIZE extension displays the maximum size in its 
EHLO response.

The RCPT check is set in
    $config->{extensions}->{size}->{rcpt_check}
When enabled, recipients are rejected up-front if delivery would cause the
mailbox to exceed its maximum size.

Enforcement of message DATA size is set in
    $config->{extensions}->{size}->{enforce}
When enabled, messages exceeding the size declared in the RCPT header
are rejected as exceeding the maximum message size.

=cut

use Modern::Perl;
use Moose;

has 'helo' => ( is => 'rw', isa => 'Str' );

#------------------------------------------------------------------------------

sub register {
	my ($self, $smtp) = @_;

	# Register this RFC
    if(!$smtp->has_rfc('RFC5321')) {
        die "MailHog::Server::SMTP::RFC1870 requires RFC5321";
    }
    $smtp->register_rfc('RFC1870', $self);

	# Add a list of commands to EHLO output
    $smtp->register_helo(sub {
        my ($session) = @_;
        return $self->helo;
    });

    # Build the helo response
    if($smtp->config->{extensions}->{size}->{broadcast}) {
        my $size = $smtp->config->{maximum_size} // "0";
        $self->helo("SIZE $size");
    } else {
        $self->helo("SIZE");
    }

    # Replace RFC5321's MAIL command
    $smtp->register_command('MAIL', sub {
        my ($session, $data) = @_;
        $self->mail($session, $data);
    });

    # Policy thing not RFC, but check if size is ok for recipient    
    if($smtp->config->{extensions}->{size}->{rcpt_check}) {
        $smtp->register_command('RCPT', sub {
            my ($session, $data) = @_;
            $self->rcpt($session, $data);
        });
    }

    # Enforcing DATA maximum size against stashed size is optional
    if($smtp->config->{extensions}->{size}->{enforce}) {
        # Capture DATA state hook so we can do a final test of message size against stash size
        $smtp->register_state('DATA', sub {
            my ($session, $data) = @_;
            $self->data($session, $data);
        });
        # Create a new state to sink data more efficiently
        $smtp->register_state('DATA_RFC1870', sub {
            my ($session, $data) = @_;
            $self->data($session, $data);
        });
    }
}

#------------------------------------------------------------------------------

sub mail {
    my ($self, $session, $data) = @_;

    if(my ($size) = $data =~ /SIZE=(\d+)/) {
        # Strip off SIZE parameter
        $data =~ s/\s*SIZE=\d+//;

        $session->log("Using MAIL from RFC1870, size provided [$size], remaining data [$data]");

        # Stash the size for the rest of the session
        $session->stash('mail_params')->{SIZE} = $size;

        # Compare against maximum size
        my $max_size = $session->smtp->config->{maximum_size} // 0;
        if($max_size > 0 && $size > $max_size) {
            # Permanent failure
            $session->respond($MailHog::Server::SMTP::ReplyCodes{EXCEEDED_STORAGE_ALLOCATION}, "Maximum message size exceeded");
            $session->log("Rejected message as too big");
            return;
        }
    }

    return $session->smtp->has_rfc('RFC5321')->mail($session, $data);
}

#------------------------------------------------------------------------------

sub rcpt {
    my ($self, $session, $data) = @_;

    # We only end up here if rcpt_check is enabled

    $session->log("Using RCPT from RFC1870 (SIZE)");

    # We need to re-check these here, otherwise we could accidentally
    # give a mailbox size error before a MAIL command
    if(!$session->stash('envelope') || !defined $session->stash('envelope')->from) {
        $session->respond($MailHog::Server::SMTP::ReplyCodes{BAD_SEQUENCE_OF_COMMANDS}, "send MAIL command first");
        return;
    }
    if(!$session->stash('envelope') || !!$session->stash('envelope')->data) {
        $session->respond($MailHog::Server::SMTP::ReplyCodes{BAD_SEQUENCE_OF_COMMANDS}, "DATA command already received");
        return;
    }

    # Unless we have a valid recipient, there's no point in checking anything
    if(my ($recipient) = $data =~ /^To:\s*<(.+)>$/i) {
        $session->log("Checking size for $recipient");
        my ($u, $d) = $recipient =~ /(.*)@(.*)/;
        my $mailbox = $session->smtp->get_mailbox($u, $d);
        if(ref($mailbox) =~ /::List$/) {
            $session->log("Mailbox is list, not checking size");
        } else {
            if($mailbox && $mailbox->{size}->{maximum} > 0) {
                if($session->stash('mail_params')->{SIZE} > $mailbox->{size}->{maximum}) {
                    # We'll return a permanent failure, on the basis that the users
                    # maximum mailbox size is unlikely to change before message expiry
                    $session->respond($MailHog::Server::SMTP::ReplyCodes{EXCEEDED_STORAGE_ALLOCATION}, "Message size exceeds mailbox size");
                    return;
                } elsif (!$mailbox->{size}->ok($session->stash('mail_params')->{SIZE})) {
                    # Could be a temporary failure, i.e. user has too many messages
                    $session->respond($MailHog::Server::SMTP::ReplyCodes{INSUFFICIENT_SYSTEM_STORAGE}, "Maximum mailbox size exceeded");
                    return;
                }
            }
        }
    }
    
    return $session->smtp->has_rfc('RFC5321')->rcpt($session, $data);
}

#------------------------------------------------------------------------------

sub data {
    my ($self, $session, $data) = @_;

    # We only end up here if enforce is enabled

    # Unless size was given in MAIL command, do nothing
    if($session->stash('mail_params')->{SIZE}) {
        # Capture the new state to sink data
        if($session->state eq 'DATA_RFC1870') {
            $session->error("DATA_RFC1870 state");
            $session->stash->{'data'} .= $session->buffer;
            $session->buffer('');

            # Once we get end of data, respond with failure
            if($session->stash('data') =~ /.*\r\n\.\r\n$/s) {
                $session->respond($MailHog::Server::SMTP::ReplyCodes{EXCEEDED_STORAGE_ALLOCATION}, "Maximum message size exceeded");
                $session->state('ERROR');
                return;
            }

            # Otherwise sink
            return;
        }

        # Test the length against the final message
        # otherwise the . gets counted and causes the size to always exceed
        my $d = $session->stash('data') . $session->buffer;
        $d =~ s/\r\n\.\r\n$//s;
        my $len = length($d);
        my $max = $session->stash('mail_params')->{SIZE};

        if($len > $max) {
            # Don't bother calling RFC5321, we'll just wait until the end
            # of the DATA input and return an error 552
            $session->error("Message length [$len] exceeds declared size [$max]");

            # Store data
            $session->stash->{'data'} .= $session->buffer;
            $session->buffer('');

            # Handle end of message here, we may have exceeded in the final line of content
            if($session->stash('data') =~ /.*\r\n\.\r\n$/s) {
                $session->respond($MailHog::Server::SMTP::ReplyCodes{EXCEEDED_STORAGE_ALLOCATION}, "Maximum message size exceeded");
                $session->state('ERROR');
                return;
            }

            # Otherwise, set new state to sink data
            $session->state('DATA_RFC1870');

            return;
        }
    }

    # Finally let RFC5321 have it
    return $session->smtp->has_rfc('RFC5321')->data($session, $data);
}

#------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;